using Pipelines, DataIngestion, DuckDBUtils, DBInterface, DataFrames, GLM, Statistics, JSON3
using Test

@testset "evaluation order" begin
    nodes = [
        Pipelines.Node(["temp"], ["pred humid"], true),
        Pipelines.Node(["pred humid"], ["pred wind"], true),
        Pipelines.Node(["wind", "wind name"], ["pred temp"], true),
        Pipelines.Node(["wind"], ["wind name"], true),
    ]

    @test Pipelines.evaluation_order!(nodes) == [4, 3, 1, 2]

    nodes = [
        Pipelines.Node(["temp"], ["pred humid"], false),
        Pipelines.Node(["pred humid"], ["pred wind"], true),
        Pipelines.Node(["wind", "wind name"], ["pred temp"], false),
        Pipelines.Node(["wind"], ["wind name"], true),
    ]

    @test Pipelines.evaluation_order!(nodes) == [4, 3, 2]
end

mktempdir() do dir
    spec = open(JSON3.read, joinpath(@__DIR__, "static", "spec.json"))
    repo = Repository(joinpath(dir, "db.duckdb"))
    DataIngestion.load_files(repo, spec["data"]["files"])
    filters = DataIngestion.get_filter.(spec["filters"])
    DataIngestion.select(repo, filters)

    @testset "split" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "split.json"))
        split = Pipelines.get_card(d["tiles"])
        Pipelines.evaluate(repo, split, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_tiled_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        # TODO: test by group as well

        split = Pipelines.get_card(d["percentile"])
        Pipelines.evaluate(repo, split, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_percentile_partition",
        ]
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
        # TODO: port TimeFunnelUtils tests

        split = Pipelines.SplitCard("percentile", String[], ["cbwd"], "_percentile_partition", 0.9, Int[])
        @test_throws ArgumentError Pipelines.evaluate(repo, split, "selection" => "split")
    end

    # TODO: also test partitioned version
    @testset "rescale" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "rescale.json"))

        resc = Pipelines.get_card(d["zscore"])
        Pipelines.evaluate(repo, resc, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]

        aux = transform(
            groupby(df, "cbwd"),
            "TEMP" => mean => "TEMP_mean",
            "TEMP" => (x -> std(x, corrected = false)) => "TEMP_std"
        )
        @test aux.TEMP_rescaled ≈ @. (aux.TEMP - aux.TEMP_mean) / aux.TEMP_std

        resc = Pipelines.get_card(d["maxabs"])
        Pipelines.evaluate(repo, resc, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]

        aux = transform(
            groupby(df, ["year", "month", "cbwd"]),
            "TEMP" => (x -> maximum(abs, x)) => "TEMP_maxabs"
        )
        @test aux.TEMP_rescaled ≈ @. aux.TEMP / aux.TEMP_maxabs

        resc = Pipelines.get_card(d["minmax"])
        Pipelines.evaluate(repo, resc, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        min, max = extrema(df.TEMP)
        @test df.TEMP_rescaled ≈ @. (df.TEMP - min) / (max - min)

        resc = Pipelines.get_card(d["log"])
        Pipelines.evaluate(repo, resc, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "PRES_rescaled",
        ]
        @test df.PRES_rescaled ≈ @. log(df.PRES)

        resc = Pipelines.get_card(d["logistic"])
        Pipelines.evaluate(repo, resc, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        @test df.TEMP_rescaled ≈ @. 1 / (1 + exp(- df.TEMP))
    end

    @testset "glm" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "glm.json"))

        part = Pipelines.get_card(d["partition"])
        Pipelines.evaluate(repo, part, "selection" => "partition")

        resc = Pipelines.get_card(d["hasPartition"])
        Pipelines.evaluate(repo, resc, "partition" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat",
            ]
        )
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition where partition = 1")
        m = glm(@formula(TEMP ~ 1 + cbwd * year + No), train_df, Normal(), IdentityLink())
        @test predict(m, df) == df.TEMP_hat

        d = open(JSON3.read, joinpath(@__DIR__, "static", "glm.json"))

        resc = Pipelines.get_card(d["hasWeights"])
        Pipelines.evaluate(repo, resc, "partition" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "PRES_hat",
            ]
        )
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
        m = glm(@formula(PRES ~ 1 + cbwd * year + No), train_df, Gamma(), wts = train_df.TEMP)
        @test predict(m, df) == df.PRES_hat
    end

    @testset "cards" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "cards.json"))
        cards = Pipelines.get_card.(d)
        Pipelines.evaluate(repo, cards, "selection")
        df = DBInterface.execute(DataFrame, repo, "FROM selection")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "_tiled_partition", "_percentile_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
    end
end
