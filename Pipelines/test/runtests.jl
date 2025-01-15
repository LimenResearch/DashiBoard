using Pipelines, DataIngestion, DuckDBUtils
using DBInterface, DataFrames, GLM, DataInterpolations, Statistics, JSON3
using Test

@testset "evaluation order" begin
    struct TrivialCard <: Pipelines.AbstractCard
        inputs::Vector{String}
        outputs::Vector{String}
    end
    Pipelines.inputs(t::TrivialCard) = Set(t.inputs)
    Pipelines.outputs(t::TrivialCard) = Set(t.outputs)

    nodes = [
        Pipelines.Node(TrivialCard(["temp"], ["pred humid"]), true),
        Pipelines.Node(TrivialCard(["pred humid"], ["pred wind"]), true),
        Pipelines.Node(TrivialCard(["wind", "wind name"], ["pred temp"]), true),
        Pipelines.Node(TrivialCard(["wind"], ["wind name"]), true),
    ]

    @test Pipelines.evaluation_order!(nodes) == [4, 3, 1, 2]

    nodes = [
        Pipelines.Node(TrivialCard(["temp"], ["pred humid"]), false),
        Pipelines.Node(TrivialCard(["pred humid"], ["pred wind"]), true),
        Pipelines.Node(TrivialCard(["wind", "wind name"], ["pred temp"]), false),
        Pipelines.Node(TrivialCard(["wind"], ["wind name"]), true),
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
        card = Pipelines.get_card(d["tiles"])

        @test issetequal(Pipelines.inputs(card), ["No", "cbwd"])
        @test issetequal(Pipelines.outputs(card), ["_tiled_partition"])

        Pipelines.evaluate(repo, card, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_tiled_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        # TODO: test by group as well

        card = Pipelines.get_card(d["percentile"])
        Pipelines.evaluate(repo, card, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_percentile_partition",
        ]
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
        # TODO: port TimeFunnelUtils tests

        card = Pipelines.SplitCard("percentile", String[], ["cbwd"], "_percentile_partition", 0.9, Int[])
        @test_throws ArgumentError Pipelines.evaluate(repo, card, "selection" => "split")
    end

    # TODO: also test partitioned version
    @testset "rescale" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "rescale.json"))

        card = Pipelines.get_card(d["zscore"])

        @test issetequal(Pipelines.inputs(card), ["cbwd", "TEMP"])
        @test issetequal(Pipelines.outputs(card), ["TEMP_rescaled"])

        Pipelines.evaluate(repo, card, "selection" => "rescaled")
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

        card = Pipelines.get_card(d["maxabs"])
        Pipelines.evaluate(repo, card, "selection" => "rescaled")
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

        card = Pipelines.get_card(d["minmax"])
        Pipelines.evaluate(repo, card, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        min, max = extrema(df.TEMP)
        @test df.TEMP_rescaled ≈ @. (df.TEMP - min) / (max - min)

        card = Pipelines.get_card(d["log"])
        Pipelines.evaluate(repo, card, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "PRES_rescaled",
        ]
        @test df.PRES_rescaled ≈ @. log(df.PRES)

        card = Pipelines.get_card(d["logistic"])
        Pipelines.evaluate(repo, card, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        @test df.TEMP_rescaled ≈ @. 1 / (1 + exp(- df.TEMP))
    end

    @testset "glm" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "glm.json"))

        part_card = Pipelines.get_card(d["partition"])
        Pipelines.evaluate(repo, part_card, "selection" => "partition")

        card = Pipelines.get_card(d["hasPartition"])

        @test issetequal(Pipelines.inputs(card), ["cbwd", "year", "No", "TEMP", "partition"])
        @test issetequal(Pipelines.outputs(card), ["TEMP_hat"])

        Pipelines.evaluate(repo, card, "partition" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat",
            ]
        )
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
        m = glm(@formula(TEMP ~ 1 + cbwd * year + No), train_df, Normal(), IdentityLink())
        @test predict(m, df) == df.TEMP_hat

        d = open(JSON3.read, joinpath(@__DIR__, "static", "glm.json"))

        card = Pipelines.get_card(d["hasWeights"])

        Pipelines.evaluate(repo, card, "partition" => "glm")
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

    @testset "interp" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "interp.json"))

        part_card = Pipelines.get_card(d["partition"])
        Pipelines.evaluate(repo, part_card, "selection" => "partition")

        card = Pipelines.get_card(d["constant"])

        @test issetequal(Pipelines.inputs(card), ["No"])
        @test issetequal(Pipelines.outputs(card), ["TEMP", "PRES"])

        Pipelines.evaluate(repo, card, "partition" => "interp")
        df = DBInterface.execute(DataFrame, repo, "FROM interp ORDER BY No")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
                "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat", "PRES_hat",
            ]
        )
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1 ORDER BY  No")
        ips = [
            ConstantInterpolation(
                train_df.TEMP,
                train_df.No,
                extrapolation_left = ExtrapolationType.Extension,
                extrapolation_right = ExtrapolationType.Extension,
                dir = :right
            ),
            ConstantInterpolation(
                train_df.PRES,
                train_df.No,
                extrapolation_left = ExtrapolationType.Extension,
                extrapolation_right = ExtrapolationType.Extension,
                dir = :right
            )
        ]

        @test ips[1](float.(df.No)) == df.TEMP_hat
        @test ips[2](float.(df.No)) == df.PRES_hat

        card = Pipelines.get_card(d["quadratic"])

        @test issetequal(Pipelines.inputs(card), ["No"])
        @test issetequal(Pipelines.outputs(card), ["TEMP", "PRES"])

        Pipelines.evaluate(repo, card, "partition" => "interp")
        df = DBInterface.execute(DataFrame, repo, "FROM interp ORDER BY No")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
                "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat", "PRES_hat",
            ]
        )
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1 ORDER BY  No")
        ips = [
            QuadraticInterpolation(
                train_df.TEMP,
                train_df.No,
                extrapolation_left = ExtrapolationType.Linear,
                extrapolation_right = ExtrapolationType.Linear
            ),
            QuadraticInterpolation(
                train_df.PRES,
                train_df.No,
                extrapolation_left = ExtrapolationType.Linear,
                extrapolation_right = ExtrapolationType.Linear
            )
        ]

        @test ips[1](float.(df.No)) == df.TEMP_hat
        @test ips[2](float.(df.No)) == df.PRES_hat
    end

    @testset "cards" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "cards.json"))
        cards = Pipelines.get_card.(d)
        Pipelines.evaluate(repo, cards, "selection")
        df = DBInterface.execute(DataFrame, repo, "FROM selection")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "_tiled_partition", "PRES_rescaled", "TEMP_rescaled",
            "_percentile_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
        # TODO: test zscore values as well
    end
end
