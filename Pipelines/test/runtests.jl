using Pipelines, DataIngestion, DuckDBUtils, DBInterface, DataFrames, GLM, Statistics, JSON3
using Test

const static_dir = joinpath(@__DIR__, "static")

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
    spec = open(JSON3.read, joinpath(static_dir, "spec.json"))
    repo = Repository(joinpath(dir, "db.duckdb"))
    DataIngestion.load_files(repo, spec["data"]["files"])
    filters = DataIngestion.get_filter.(spec["filters"])
    DataIngestion.select(filters, repo)

    @testset "split" begin
        d = open(JSON3.read, joinpath(static_dir, "split.json"))
        split = Pipelines.get_card(d["tiles"])
        Pipelines.evaluate(split, repo, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_tiled_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        # TODO: test by group as well

        split = Pipelines.get_card(d["percentile"])
        Pipelines.evaluate(split, repo, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_percentile_partition",
        ]
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
        # TODO: port TimeFunnelUtils tests

        split = Pipelines.SplitCard("percentile", String[], ["cbwd"], "_percentile_partition", 0.9, Int[])
        @test_throws ArgumentError Pipelines.evaluate(split, repo, "selection" => "split")
    end

    # TODO: also test partitioned version
    @testset "rescale" begin
        d = open(JSON3.read, joinpath(static_dir, "rescale.json"))

        resc = Pipelines.get_card(d["zscore"])
        Pipelines.evaluate(resc, repo, "selection" => "rescaled")
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
        Pipelines.evaluate(resc, repo, "selection" => "rescaled")
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
        Pipelines.evaluate(resc, repo, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        min, max = extrema(df.TEMP)
        @test df.TEMP_rescaled ≈ @. (df.TEMP - min) / (max - min)

        resc = Pipelines.get_card(d["log"])
        Pipelines.evaluate(resc, repo, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "PRES_rescaled",
        ]
        @test df.PRES_rescaled ≈ @. log(df.PRES)

        resc = Pipelines.get_card(d["logistic"])
        Pipelines.evaluate(resc, repo, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        @test df.TEMP_rescaled ≈ @. 1 / (1 + exp(- df.TEMP))
    end

    @testset "glm" begin
        d = open(JSON3.read, joinpath(static_dir, "glm.json"))

        resc = Pipelines.get_card(d["hasLink"])
        Pipelines.evaluate(resc, repo, "selection" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_hat",
            ]
        )
        sel = DBInterface.execute(DataFrame, repo, "FROM selection")
        m = glm(@formula(TEMP ~ 1 + cbwd * year + No), sel, Normal(), IdentityLink())
        @test predict(m) == df.TEMP_hat

        d = open(JSON3.read, joinpath(static_dir, "glm.json"))

        resc = Pipelines.get_card(d["hasWeights"])
        Pipelines.evaluate(resc, repo, "selection" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "PRES_hat",
            ]
        )
        sel = DBInterface.execute(DataFrame, repo, "FROM selection")
        m = glm(@formula(PRES ~ 1 + cbwd * year + No), sel, Gamma(), wts = sel.TEMP)
        @test predict(m) == df.PRES_hat
    end

    @testset "cards" begin
        d = open(JSON3.read, joinpath(static_dir, "cards.json"))
        cards = Pipelines.get_card.(d)
        Pipelines.evaluate(cards, repo, "selection")
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
