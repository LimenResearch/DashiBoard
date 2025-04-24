mktempdir() do dir
    spec = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "spec.json"))
    repo = Repository(joinpath(dir, "db.duckdb"))
    DataIngestion.load_files(repo, spec["data"]["files"])
    filters = DataIngestion.get_filter.(spec["filters"])
    DataIngestion.select(repo, filters)

    @testset "split" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "split.json"))
        card = Pipelines.get_card(d["tiles"])
        @test !Pipelines.invertible(card)

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

        @test_throws ArgumentError Pipelines.get_card(d["unsorted"])
    end

    # TODO: also test partitioned version
    @testset "rescale" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "rescale.json"))

        card = Pipelines.get_card(d["zscore"])
        @test Pipelines.invertible(card)

        @test issetequal(Pipelines.inputs(card), ["cbwd", "TEMP"])
        @test issetequal(Pipelines.outputs(card), ["TEMP_rescaled"])

        state = Pipelines.evaluate(repo, card, "selection" => "rescaled")
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

        DBInterface.execute(
            Returns(nothing),
            repo,
            """
            CREATE OR REPLACE TABLE tbl AS
            SELECT cbwd, TEMP_rescaled FROM rescaled;
            """
        )
        Pipelines.evaluate(repo, card, state, "tbl" => "inverted", invert = true)
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.TEMP ≈ df.TEMP

        card = Pipelines.get_card(d["maxabs"])
        state = Pipelines.evaluate(repo, card, "selection" => "rescaled")
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

        DBInterface.execute(
            Returns(nothing),
            repo,
            """
            CREATE OR REPLACE TABLE tbl AS
            SELECT year, month, cbwd, TEMP_rescaled FROM rescaled;
            """
        )
        Pipelines.evaluate(repo, card, state, "tbl" => "inverted", invert = true)
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.TEMP ≈ df.TEMP

        card = Pipelines.get_card(d["minmax"])
        state = Pipelines.evaluate(repo, card, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled",
        ]
        min, max = extrema(df.TEMP)
        @test df.TEMP_rescaled ≈ @. (df.TEMP - min) / (max - min)

        DBInterface.execute(
            Returns(nothing),
            repo,
            """
            CREATE OR REPLACE TABLE tbl AS
            SELECT TEMP_rescaled FROM rescaled;
            """
        )
        Pipelines.evaluate(repo, card, state, "tbl" => "inverted", invert = true)
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.TEMP ≈ df.TEMP

        card = Pipelines.get_card(d["log"])
        state = Pipelines.evaluate(repo, card, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "PRES_rescaled",
        ]
        @test df.PRES_rescaled ≈ @. log(df.PRES)

        DBInterface.execute(
            Returns(nothing),
            repo,
            """
            CREATE OR REPLACE TABLE tbl AS
            SELECT PRES_rescaled FROM rescaled;
            """
        )
        Pipelines.evaluate(repo, card, state, "tbl" => "inverted", invert = true)
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.PRES ≈ df.PRES

        card = Pipelines.get_card(d["logistic"])
        state = Pipelines.evaluate(repo, card, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "hour_rescaled",
        ]
        @test df.hour_rescaled ≈ @. 1 / (1 + exp(- df.hour))

        DBInterface.execute(
            Returns(nothing),
            repo,
            """
            CREATE OR REPLACE TABLE tbl AS
            SELECT hour_rescaled FROM rescaled;
            """
        )
        Pipelines.evaluate(repo, card, state, "tbl" => "inverted", invert = true)
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.hour ≈ df.hour
    end

    @testset "cluster" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "cluster.json"))

        card = Pipelines.get_card(d["kmeans"])

        @test !Pipelines.invertible(card)
        @test issetequal(Pipelines.inputs(card), ["TEMP", "PRES"])
        @test issetequal(Pipelines.outputs(card), ["cluster"])

        Pipelines.evaluate(repo, card, "selection" => "clustering")
        df = DBInterface.execute(DataFrame, repo, "FROM clustering")
        @test issetequal(
            names(df),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "cluster",
            ]
        )

        train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
        rng = StreamlinerCore.get_rng(1234)
        R = kmeans([train_df.TEMP train_df.PRES]', 3; maxiter = 100, tol = 1e-6, rng)
        @test assignments(R) == df.cluster
    end

    @testset "glm" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "glm.json"))

        part_card = Pipelines.get_card(d["partition"])
        Pipelines.evaluate(repo, part_card, "selection" => "partition")

        card = Pipelines.get_card(d["hasPartition"])
        @test !Pipelines.invertible(card)

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

        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "glm.json"))

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
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "interp.json"))

        part_card = Pipelines.get_card(d["partition"])
        Pipelines.evaluate(repo, part_card, "selection" => "partition")

        card = Pipelines.get_card(d["constant"])
        @test !Pipelines.invertible(card)

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
        selection = DBInterface.execute(DataFrame, repo, "FROM selection")
        origin = transform(
            selection,
            [:year, :month, :day] => ByRow((y, m, d) -> Date(y, m, d)) => :date,
            :hour => ByRow(x -> Time(x, 0)) => :time
        )

        DuckDBUtils.load_table(repo, origin, "origin")

        @testset "GaussianEncodingCard construction" begin
            base_fields = Dict(
                :column => "date",
                :n_modes => 3,
                :max => 365.0,
                :lambda => 0.5,
                :suffix => "gaussian"
            )

            for (k, v) in pairs(Pipelines.TEMPORAL_PREPROCESSING)
                config = merge(base_fields, Dict(:method => k))
                card = GaussianEncodingCard(config)
                @test string(card.processed_column) == string(v(Get("date")))
            end

            invalid_method = "nonexistent_method"
            invalid_config = merge(base_fields, Dict(:method => invalid_method))
            @test_throws ArgumentError GaussianEncodingCard(invalid_config)

            invalid_config = Dict(
                :column => "date",
                :n_modes => 0,
                :max => 365.0,
                :lambda => 0.5,
                :method => "identity"
            )
            @test_throws ArgumentError GaussianEncodingCard(invalid_config)
        end

        function gauss_train_test(card, state)
            expected_means = range(0, step = 1 / card.n_modes, length = card.n_modes)
            expected_sigma = step(expected_means) * card.lambda
            expected_d = card.max
            expected_keys = vcat(["μ_$i" for i in 1:card.n_modes], ["σ", "d"])

            params = Pipelines.jlddeserialize(state.content)
            @test isempty(setdiff(expected_keys, keys(params)))
            @test all([params["μ_$i"] == [v] for (i, v) in enumerate(expected_means)])
            @test params["σ"][1] ≈ expected_sigma
            @test params["d"][1] ≈ expected_d
        end

        _rem(x) = rem(x, 1, RoundNearest)
        function gauss_evaluate_test(result, card, origin; processing)
            @test issetequal(
                names(result),
                union(names(origin), Pipelines.outputs(card))
            )

            origin_column = origin[:, card.column]
            max_value = card.max
            preprocessed_values = processing.(origin_column)
            μs = range(0, step = 1 / card.n_modes, length = card.n_modes)
            σ = step(μs) * card.lambda
            for (i, μ) in enumerate(μs)
                expected_values = pdf.(Normal(0, σ), _rem.(preprocessed_values ./ max_value .- μ)) .* σ
                @test result[:, "$(card.column)_gaussian_$i"] ≈ expected_values
            end
        end

        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.get_card(d["identity"])
        @test !Pipelines.invertible(card)
        state = Pipelines.evaluate(repo, card, "origin" => "encoded")
        gauss_train_test(card, state)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, card, origin; processing = identity)
        @test issetequal(Pipelines.outputs(card), ["month_gaussian_1", "month_gaussian_2", "month_gaussian_3", "month_gaussian_4"])
        @test only(Pipelines.inputs(card)) == "month"

        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.get_card(d["dayofyear"])
        state = Pipelines.evaluate(repo, card, "origin" => "encoded")
        gauss_train_test(card, state)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, card, origin; processing = dayofyear)
        @test issetequal(
            Pipelines.outputs(card),
            [
                "date_gaussian_1", "date_gaussian_2", "date_gaussian_3", "date_gaussian_4",
                "date_gaussian_5", "date_gaussian_6", "date_gaussian_7", "date_gaussian_8",
                "date_gaussian_9", "date_gaussian_10", "date_gaussian_11", "date_gaussian_12",
            ]
        )
        @test only(Pipelines.inputs(card)) == "date"

        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.get_card(d["hour"])
        state = Pipelines.evaluate(repo, card, "origin" => "encoded")
        gauss_train_test(card, state)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, card, origin; processing = hour)
        @test issetequal(Pipelines.outputs(card), ["time_gaussian_1", "time_gaussian_2", "time_gaussian_3", "time_gaussian_4"])
        @test only(Pipelines.inputs(card)) == "time"

        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.get_card(d["minute"])
        state = Pipelines.evaluate(repo, card, "origin" => "encoded")
        gauss_train_test(card, state)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, card, origin; processing = minute)
        @test issetequal(Pipelines.outputs(card), ["time_gaussian_1"])
        @test only(Pipelines.inputs(card)) == "time"
    end

    @testset "streamliner" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "streamliner.json"))

        part_card = Pipelines.get_card(d["partition"])
        Pipelines.evaluate(repo, part_card, "selection" => "partition")

        model_directory = joinpath(@__DIR__, "static", "model")
        training_directory = joinpath(@__DIR__, "static", "training")
        card = @with(
            Pipelines.PARSER => Pipelines.default_parser(),
            Pipelines.MODEL_DIR => model_directory,
            Pipelines.TRAINING_DIR => training_directory,
            Pipelines.get_card(d["basic"]),
        )
        @test !Pipelines.invertible(card)

        state = Pipelines.train(repo, card, "partition")
        res = state.metadata
        @test res["iteration"] == 4
        @test !res["resumed"]
        @test length(res["stats"][1]) == length(res["stats"][2]) == 2
        @test res["successful"]
        @test res["trained"]

        Pipelines.evaluate(repo, card, "partition" => "prediction")
        origin = DBInterface.execute(DataFrame, repo, "FROM partition")
        result = DBInterface.execute(DataFrame, repo, "FROM prediction")
        @test issetequal(
            names(result),
            [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
                "cbwd", "Iws", "Is", "Ir", "_name", "partition", "Iws_hat",
            ]
        )
        @test all(!ismissing, result.Iws_hat)
        @test nrow(origin) == nrow(result)
    end
end
