mktempdir() do dir
    spec = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "spec.json"))
    repo = Repository(joinpath(dir, "db.duckdb"))
    Downloads.download(
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
        joinpath(dir, "pollution.csv")
    )
    DataIngestion.load_files(repo, dir, spec["data"])
    filters = DataIngestion.Filter.(spec["filters"])
    DataIngestion.select(repo, filters)

    @testset "split" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "split.json"))
        card = Pipelines.Card(d["tiles"])
        @test !Pipelines.invertible(card)

        @test Pipelines.get_inputs(card) == ["No", "cbwd"]
        @test Pipelines.get_outputs(card) == ["_tiled_partition"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_tiled_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        # TODO: test by group as well

        card = Pipelines.Card(d["percentile"])
        node = Node(card)
        @test_throws ArgumentError invert(node)
        Pipelines.train_evaljoin!(repo, node, "selection" => "split")
        df = DBInterface.execute(DataFrame, repo, "FROM split")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_percentile_partition",
        ]
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
        # TODO: port TimeFunnelUtils tests

        @test_throws ArgumentError Pipelines.Card(d["unsorted"])
    end

    # TODO: also test partitioned version
    @testset "rescale" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "rescale.json"))

        card = Pipelines.Card(d["zscore"])
        @test Pipelines.invertible(card)

        @test Pipelines.get_inputs(card) == ["cbwd", "TEMP"]
        @test Pipelines.get_outputs(card) == ["TEMP_rescaled"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled")
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
        Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted")
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.TEMP ≈ df.TEMP

        card = Pipelines.Card(d["zscore_flipped"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled")
        df = DBInterface.execute(DataFrame, repo, "FROM rescaled")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "TEMP_rescaled", "PRES_rescaled",
        ]

        TEMP_mean, TEMP_std = mean(df.TEMP), std(df.TEMP, corrected = false)
        PRES_mean, PRES_std = mean(df.PRES), std(df.PRES, corrected = false)

        @test df.TEMP_rescaled ≈ @. (df.TEMP - TEMP_mean) / TEMP_std
        @test df.PRES_rescaled ≈ @. (df.PRES - PRES_mean) / PRES_std
        DBInterface.execute(
            Returns(nothing),
            repo,
            # Simulate that we have a `PRES_hat_rescaled` column to denormalize
            """
            CREATE OR REPLACE TABLE tbl AS
            SELECT TEMP_rescaled AS PRES_rescaled_hat FROM rescaled;
            """
        )

        Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted")
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.PRES_hat ≈ @. PRES_mean + df.TEMP_rescaled * PRES_std

        card = Pipelines.Card(d["maxabs"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled")
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
        Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted")
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.TEMP ≈ df.TEMP

        card = Pipelines.Card(d["minmax"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled")
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
        Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted")
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.TEMP ≈ df.TEMP

        card = Pipelines.Card(d["log"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled")
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
        Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted")
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.PRES ≈ df.PRES

        card = Pipelines.Card(d["logistic"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled")
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
        Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted")
        df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
        @test df′.hour ≈ df.hour
    end

    @testset "cluster" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cluster.json"))

        card = Pipelines.Card(d["kmeans"])

        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["TEMP", "PRES"]
        @test Pipelines.get_outputs(card) == ["cluster"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "clustering")
        df = DBInterface.execute(DataFrame, repo, "FROM clustering")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "cluster",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
        rng = StreamlinerCore.get_rng(1234)
        R = kmeans([train_df.TEMP train_df.PRES]', 3; maxiter = 100, tol = 1.0e-6, rng)
        @test assignments(R) == df.cluster

        card = Pipelines.Card(d["dbscan"])

        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["TEMP", "PRES"]
        @test Pipelines.get_outputs(card) == ["dbcluster"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "selection" => "clustering")
        df = DBInterface.execute(DataFrame, repo, "FROM clustering")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "dbcluster",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
        R = dbscan([train_df.TEMP train_df.PRES]', 0.02)
        @test assignments(R) == df.dbcluster
    end

    @testset "dimensionality reduction" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "dimres.json"))

        DBInterface.execute(
            Returns(nothing),
            repo,
            """
            CREATE OR REPLACE TABLE small AS (
                FROM selection
                LIMIT 100
            );
            """
        )
        part_card = Pipelines.Card(d["partition"])
        part_node = Node(part_card)
        Pipelines.train_evaljoin!(repo, part_node, "small" => "partition")

        card = Pipelines.Card(d["pca"])

        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["DEWP", "TEMP", "PRES", "partition"]
        @test Pipelines.get_outputs(card) == ["component_1", "component_2"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "dimres")
        df = DBInterface.execute(DataFrame, repo, "FROM dimres")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "partition", "component_1", "component_2",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
        model = fit(PCA, [train_df.DEWP train_df.TEMP train_df.PRES]', maxoutdim = 2)
        X = [df.DEWP df.TEMP df.PRES]'
        Y = predict(model, X)
        @test Y[1, :] == df.component_1
        @test Y[2, :] == df.component_2

        card = Pipelines.Card(d["ppca"])

        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["DEWP", "TEMP", "PRES", "partition"]
        @test Pipelines.get_outputs(card) == ["component_1", "component_2"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "dimres")
        df = DBInterface.execute(DataFrame, repo, "FROM dimres")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "partition", "component_1", "component_2",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
        model = fit(
            PPCA,
            [train_df.DEWP train_df.TEMP train_df.PRES]',
            maxoutdim = 2,
            tol = 1.0e-5,
            maxiter = 100
        )
        X = [df.DEWP df.TEMP df.PRES]'
        Y = predict(model, X)
        @test Y[1, :] == df.component_1
        @test Y[2, :] == df.component_2

        card = Pipelines.Card(d["factoranalysis"])

        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["DEWP", "TEMP", "PRES", "partition"]
        @test Pipelines.get_outputs(card) == ["component_1", "component_2"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "dimres")
        df = DBInterface.execute(DataFrame, repo, "FROM dimres")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "partition", "component_1", "component_2",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
        model = fit(
            FactorAnalysis,
            [train_df.DEWP train_df.TEMP train_df.PRES]',
            maxoutdim = 2,
            tol = 1.0e-5,
            maxiter = 100
        )
        X = [df.DEWP df.TEMP df.PRES]'
        Y = predict(model, X)
        @test Y[1, :] == df.component_1
        @test Y[2, :] == df.component_2

        card = Pipelines.Card(d["mds"])

        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["DEWP", "TEMP", "PRES", "partition"]
        @test Pipelines.get_outputs(card) == ["component_1", "component_2"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "dimres")
        df = DBInterface.execute(DataFrame, repo, "FROM dimres")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "partition", "component_1", "component_2",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
        model = fit(
            MDS,
            [train_df.DEWP train_df.TEMP train_df.PRES]',
            maxoutdim = 2,
            distances = false
        )
        X = [df.DEWP df.TEMP df.PRES]'
        Y = stack(x -> vec(predict(model, x)), eachcol(X))
        @test Y[1, :] == df.component_1
        @test Y[2, :] == df.component_2
    end

    @testset "glm" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))

        part_card = Pipelines.Card(d["partition"])
        part_node = Node(part_card)
        Pipelines.train_evaljoin!(repo, part_node, "selection" => "partition")

        card = Pipelines.Card(d["hasPartition"])
        @test !Pipelines.invertible(card)

        @test Pipelines.get_inputs(card) == ["cbwd", "year", "No", "TEMP", "partition"]
        @test Pipelines.get_outputs(card) == ["TEMP_hat"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat",
        ]
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
        m = glm(@formula(TEMP ~ 1 + cbwd * year + No), train_df, Normal(), IdentityLink())
        @test predict(m, df) == df.TEMP_hat

        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))

        card = Pipelines.Card(d["hasWeights"])

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "glm")
        df = DBInterface.execute(DataFrame, repo, "FROM glm")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "PRES_hat",
        ]
        train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
        m = glm(@formula(PRES ~ 1 + cbwd * year + No), train_df, Gamma(), wts = train_df.TEMP)
        @test predict(m, df) == df.PRES_hat
    end

    @testset "interp" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "interp.json"))

        part_card = Pipelines.Card(d["partition"])
        part_node = Node(part_card)
        Pipelines.train_evaljoin!(repo, part_node, "selection" => "partition")

        card = Pipelines.Card(d["constant"])
        @test !Pipelines.invertible(card)

        @test Pipelines.get_inputs(card) == ["No", "TEMP", "PRES", "partition"]
        @test Pipelines.get_outputs(card) == ["TEMP_hat", "PRES_hat"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "interp")
        df = DBInterface.execute(DataFrame, repo, "FROM interp ORDER BY No")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
            "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat", "PRES_hat",
        ]
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

        card = Pipelines.Card(d["quadratic"])

        @test Pipelines.get_inputs(card) == ["No", "TEMP", "PRES", "partition"]
        @test Pipelines.get_outputs(card) == ["TEMP_hat", "PRES_hat"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "interp")
        df = DBInterface.execute(DataFrame, repo, "FROM interp ORDER BY No")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
            "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat", "PRES_hat",
        ]
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
                "type" => "gaussian_encoding",
                "input" => "date",
                "n_modes" => 3,
                "max" => 365.0,
                "lambda" => 0.5,
                "suffix" => "gaussian"
            )

            for (k, v) in pairs(Pipelines.TEMPORAL_PREPROCESSING)
                c = merge(base_fields, Dict("method" => k))
                card = GaussianEncodingCard(c)
                @test string(card.processed_input) == string(v(Get("date")))
            end

            invalid_method = "nonexistent_method"
            invalid_config = merge(base_fields, Dict("method" => invalid_method))
            @test_throws ArgumentError GaussianEncodingCard(invalid_config)

            invalid_config = Dict(
                "type" => "gaussian_encoding",
                "input" => "date",
                "n_modes" => 0,
                "max" => 365.0,
                "lambda" => 0.5,
                "method" => "identity"
            )
            @test_throws ArgumentError GaussianEncodingCard(invalid_config)
        end

        function gauss_train_test(node::Node)
            card, state = get_card(node), get_state(node)
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
        function gauss_evaluate_test(result, node::Node, origin; processing)
            card = get_card(node)
            @test names(result) == union(names(origin), Pipelines.get_outputs(card))

            origin_column = origin[:, card.input]
            max_value = card.max
            preprocessed_values = processing.(origin_column)
            μs = range(0, step = 1 / card.n_modes, length = card.n_modes)
            σ = step(μs) * card.lambda
            for (i, μ) in enumerate(μs)
                expected_values = pdf.(Normal(0, σ), _rem.(preprocessed_values ./ max_value .- μ)) .* σ
                @test result[:, "$(card.input)_gaussian_$i"] ≈ expected_values
            end
        end

        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.Card(d["identity"])
        node = Node(card)
        @test !Pipelines.invertible(node)
        Pipelines.train_evaljoin!(repo, node, "origin" => "encoded")
        gauss_train_test(node)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, node, origin; processing = identity)
        @test Pipelines.get_outputs(card) == ["month_gaussian_1", "month_gaussian_2", "month_gaussian_3", "month_gaussian_4"]
        @test Pipelines.get_inputs(card) == ["month"]

        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.Card(d["dayofyear"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "origin" => "encoded")
        gauss_train_test(node)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, node, origin; processing = dayofyear)
        @test Pipelines.get_outputs(card) == [
            "date_gaussian_1", "date_gaussian_2", "date_gaussian_3", "date_gaussian_4",
            "date_gaussian_5", "date_gaussian_6", "date_gaussian_7", "date_gaussian_8",
            "date_gaussian_9", "date_gaussian_10", "date_gaussian_11", "date_gaussian_12",
        ]
        @test Pipelines.get_inputs(card) == ["date"]

        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.Card(d["hour"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "origin" => "encoded")
        gauss_train_test(node)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, node, origin; processing = hour)
        @test Pipelines.get_outputs(card) == ["time_gaussian_1", "time_gaussian_2", "time_gaussian_3", "time_gaussian_4"]
        @test only(Pipelines.get_inputs(card)) == "time"

        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian.json"))
        card = Pipelines.Card(d["minute"])
        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "origin" => "encoded")
        gauss_train_test(node)
        result = DBInterface.execute(DataFrame, repo, "FROM encoded")
        gauss_evaluate_test(result, node, origin; processing = minute)
        @test Pipelines.get_outputs(card) == ["time_gaussian_1"]
        @test only(Pipelines.get_inputs(card)) == "time"
    end

    @testset "streamliner" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "streamliner.json"))

        part_card = Pipelines.Card(d["partition"])
        part_node = Node(part_card)
        Pipelines.train_evaljoin!(repo, part_node, "selection" => "partition")

        model_directory = joinpath(@__DIR__, "static", "model")
        training_directory = joinpath(@__DIR__, "static", "training")

        card = @with(
            Pipelines.PARSER => Pipelines.default_parser(),
            Pipelines.MODEL_DIR => model_directory,
            Pipelines.TRAINING_DIR => training_directory,
            Pipelines.Card(d["basic"]),
        )
        @test !Pipelines.invertible(card)
        @test Pipelines.get_inputs(card) == ["No", "TEMP", "PRES", "Iws", "partition"]
        @test Pipelines.get_outputs(card) == ["Iws_hat"]

        node = Node(card)
        Pipelines.train!(repo, node, "partition")
        state = get_state(node)
        res = state.metadata
        @test res["iteration"] == 4
        @test !res["resumed"]
        @test length(res["stats"][1]) == length(res["stats"][2]) == 2
        @test res["successful"]
        @test res["trained"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "prediction")
        origin = DBInterface.execute(DataFrame, repo, "FROM partition")
        result = DBInterface.execute(DataFrame, repo, "FROM prediction")
        @test names(result) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
            "cbwd", "Iws", "Is", "Ir", "_name", "partition", "Iws_hat",
        ]
        @test all(!ismissing, result.Iws_hat)
        @test nrow(origin) == nrow(result)

        card = @with(
            Pipelines.PARSER => Pipelines.default_parser(),
            Pipelines.MODEL_DIR => model_directory,
            Pipelines.TRAINING_DIR => training_directory,
            Pipelines.Card(d["classifier"]),
        )
        @test !Pipelines.invertible(card)

        node = Node(card)
        Pipelines.train!(repo, node, "partition")
        state = get_state(node)
        res = state.metadata
        @test res["iteration"] == 4
        @test !res["resumed"]
        @test length(res["stats"][1]) == length(res["stats"][2]) == 2
        @test res["successful"]
        @test res["trained"]

        node = Node(card)
        Pipelines.train_evaljoin!(repo, node, "partition" => "prediction")
        state = get_state(node)
        origin = DBInterface.execute(DataFrame, repo, "FROM partition")
        result = DBInterface.execute(DataFrame, repo, "FROM prediction")
        @test names(result) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES",
            "cbwd", "Iws", "Is", "Ir", "_name", "partition", "cbwd_hat",
        ]
        @test all(x -> x isa AbstractString, result.cbwd_hat)
        @test nrow(origin) == nrow(result)

        stats = Pipelines.report(repo, card, state)
        @test stats["training"]["accuracy"] ≈ 0.34 atol = 1.0e-2
        @test stats["validation"]["accuracy"] ≈ 0.36 atol = 1.0e-2
        @test stats["training"]["logitcrossentropy"] ≈ 2.82 atol = 1.0e-2
        @test stats["validation"]["logitcrossentropy"] ≈ 1.69 atol = 1.0e-2
    end
end
