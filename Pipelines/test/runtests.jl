using Pipelines, DataIngestion, DuckDBUtils
using DBInterface, DataFrames, GLM, DataInterpolations, Statistics, JSON3
using OrderedCollections, Dates, Distributions
using Test

@testset "evaluation order" begin
    struct TrivialCard <: Pipelines.AbstractCard
        inputs::Vector{String}
        outputs::Vector{String}
    end
    Pipelines.inputs(t::TrivialCard) = OrderedSet(t.inputs)
    Pipelines.outputs(t::TrivialCard) = OrderedSet(t.outputs)

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

        @test issetequal(Pipelines.inputs(card), ["No", "TEMP", "PRES", "partition"])
        @test issetequal(Pipelines.outputs(card), ["TEMP_hat", "PRES_hat"])

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
            ),
        ]

        @test ips[1](float.(df.No)) == df.TEMP_hat
        @test ips[2](float.(df.No)) == df.PRES_hat

        card = Pipelines.get_card(d["quadratic"])

        @test issetequal(Pipelines.inputs(card), ["No", "TEMP", "PRES", "partition"])
        @test issetequal(Pipelines.outputs(card), ["TEMP_hat", "PRES_hat"])

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
            ),
        ]

        @test ips[1](float.(df.No)) == df.TEMP_hat
        @test ips[2](float.(df.No)) == df.PRES_hat
    end

    @testset "gaussian encoding" begin
        spec = open(JSON3.read, joinpath(@__DIR__, "static", "spec.json"))
        repo = Repository(joinpath(dir, "db.duckdb"))
        DataIngestion.load_files(repo, spec["data"]["files"])
        filters = DataIngestion.get_filter.(spec["filters"])
        DataIngestion.select(repo, filters)
        selection = DBInterface.execute(DataFrame, repo, "FROM selection")
        origin = transform(
            selection,
            [:year, :month, :day] => ByRow((y, m, d) -> Date(y, m, d)) => :date,
            :hour => ByRow(x -> Time(x, 0)) => :time
        )

        DuckDBUtils.load_table(repo, origin, "origin")

        @testset "GaussianEncodingCard construction" begin
            base_fields = (column = "date", means = 3, max = 365.0, coef = 0.5, suffix = "gaussian")

            for method in keys(Pipelines.GAUSSIAN_METHODS)
                fields = merge(base_fields, (method = method,))
                card = GaussianEncodingCard(; fields...)
                @test card.method == method
            end

            invalid_method = "nonexistent_method"
            invalid_fields = merge(base_fields, (method = invalid_method,))
            @test_throws ArgumentError GaussianEncodingCard(; invalid_fields...)
            @test_throws ArgumentError GaussianEncodingCard(column = "date", means = 1, max = 365.0, coef = 0.5, method = "identity")
        end

        function gauss_train_test(card, params)
            expected_means = range(0, stop = 1, length = card.means)
            expected_sigma = step(expected_means) * card.coef
            expected_d = card.max
            expected_keys = vcat(["μ_$i" for i in 1:card.means], ["σ", "d"])

            @test isempty(setdiff(expected_keys, keys(params)))
            @test all([params["μ_$i"] == [v] for (i, v) in enumerate(expected_means)])
            @test params["σ"][1] ≈ expected_sigma
            @test params["d"][1] ≈ expected_d
        end

        function gauss_evaluate_test(result, card, origin)
            @test issetequal(
                names(result),
                union(names(origin), Pipelines.outputs(card))
            )

            origin_column = origin[:, card.column]
            max_value = card.max
            preprocessed_values = [eval(Meta.parse(card.method))(x) for x in origin_column]
            μs = range(0, stop = 1, length = card.means)
            σ = step(μs) * card.coef
            dists = [Normal(μ, σ) for μ in μs]
            for (i, dist) in enumerate(dists)
                expected_values = [pdf(dist, x / max_value) for x in preprocessed_values]
                @test result[:, "$(card.column)_gaussian_$i"] ≈ expected_values
            end
        end

        d = open(JSON3.read, joinpath(@__DIR__, "static", "gaussian.json"))
        gaus = Pipelines.get_card(d["identity"])
        params = Pipelines.evaluate(repo, gaus, "origin" => "encoded")
        gauss_train_test(gaus, params)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, gaus, origin)
        @test issetequal(Pipelines.outputs(gaus), ["month_gaussian_1", "month_gaussian_2", "month_gaussian_3", "month_gaussian_4"])
        @test only(Pipelines.inputs(gaus)) == "month"

        d = open(JSON3.read, joinpath(@__DIR__, "static", "gaussian.json"))
        gaus = Pipelines.get_card(d["dayofyear"])
        params = Pipelines.evaluate(repo, gaus, "origin" => "encoded")
        gauss_train_test(gaus, params)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, gaus, origin)
        @test issetequal(
            Pipelines.outputs(gaus),
            [
                "date_gaussian_1", "date_gaussian_2", "date_gaussian_3", "date_gaussian_4",
                "date_gaussian_5", "date_gaussian_6", "date_gaussian_7", "date_gaussian_8",
                "date_gaussian_9", "date_gaussian_10", "date_gaussian_11", "date_gaussian_12",
            ]
        )
        @test only(Pipelines.inputs(gaus)) == "date"

        d = open(JSON3.read, joinpath(@__DIR__, "static", "gaussian.json"))
        gaus = Pipelines.get_card(d["hour"])
        params = Pipelines.evaluate(repo, gaus, "origin" => "encoded")
        gauss_train_test(gaus, params)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, gaus, origin)
        @test issetequal(Pipelines.outputs(gaus), ["time_gaussian_1", "time_gaussian_2", "time_gaussian_3", "time_gaussian_4"])
        @test only(Pipelines.inputs(gaus)) == "time"
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

@testset "configurations" begin
    configs = Pipelines.card_configurations()
    @test configs isa AbstractVector
    @test length(configs) == 4
end
