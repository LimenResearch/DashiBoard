spec = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "spec.json"))
repo = Repository()

mktempdir() do dir
    Downloads.download(
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
        joinpath(dir, "pollution.csv")
    )
    DataIngestion.load_files(repo, dir, spec["data"])
end

filters = DataIngestion.Filter.(spec["filters"])
DataIngestion.select(repo, filters)

@testset "split" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "split.json"))
    card = Pipelines.Card(d["tiles"])
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["No", "cbwd"]
    @test Pipelines.get_node_outputs(node) == ["_tiled_partition"]

    Pipelines.train_evaljoin!(repo, node, "selection" => "split", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM split")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_tiled_partition",
    ]
    @test count(==(1), df._tiled_partition) == 29218
    @test count(==(2), df._tiled_partition) == 14606

    # test repeating strategy
    card = Pipelines.Card(d["tiles2"])
    str, _ = DuckDBUtils.render_params(
        DuckDBUtils.get_catalog(repo),
        Partition() |> Select(card.output => Pipelines.get_sql(card.splitter))
    )
    @test str == "SELECT list_extract(list_value(1, 1, 2), \
        ((((ntile(7) OVER ()) - 1) % 3) + 1)) AS \"_tiled_partition\""
    node = Node(card)

    Pipelines.train_evaljoin!(repo, node, "selection" => "split", "No")
    v1 = DBInterface.execute(DataFrame, repo, "FROM split")._tiled_partition

    card = Pipelines.Card(d["tiles3"])
    str, _ = DuckDBUtils.render_params(
        DuckDBUtils.get_catalog(repo),
        Partition() |> Select(card.output => Pipelines.get_sql(card.splitter))
    )
    @test str == "SELECT list_extract(list_value(1, 1, 2, 1, 1, 2, 1), \
        ((((ntile(7) OVER ()) - 1) % 7) + 1)) AS \"_tiled_partition\""
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "split", "No")
    v2 = DBInterface.execute(DataFrame, repo, "FROM split")._tiled_partition
    @test v1 == v2

    # TODO: test by group as well

    card = Pipelines.Card(d["percentile"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "split", "No")
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

@testset "widow_function" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "window_function.json"))
    card = Pipelines.Card(d["row_number"])
    @test !Pipelines.invertible(card)
    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["No", "cbwd"]
    @test Pipelines.get_node_outputs(node) == ["_row_number"]

    Pipelines.train_evaljoin!(repo, node, "selection" => "output", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM output")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_row_number",
    ]
    for dd in groupby(df, :cbwd)
        sorted = sort(dd, :No)
        @test sorted._row_number == axes(sorted.No, 1)
    end

    card = Pipelines.Card(d["percent_rank"])
    node = Node(card)

    Pipelines.train_evaljoin!(repo, node, "selection" => "output", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM output")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_percent_rank",
    ]
    for dd in groupby(df, :cbwd)
        sorted = sort(dd, :No)
        @test sorted._percent_rank ≈ (denserank(sorted.No) .- 1) ./ (length(sorted.No) - 1)
    end

    card = Pipelines.Card(d["rank"])
    node = Node(card)

    Pipelines.train_evaljoin!(repo, node, "selection" => "output", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM output")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_rank",
    ]
    for dd in groupby(df, :cbwd)
        sorted = sort(dd, :No)
        @test sorted._rank == denserank(sorted.No)
    end
end

# TODO: also test partitioned version
@testset "rescale" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "rescale.json"))

    card = Pipelines.Card(d["zscore"])
    @test Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["cbwd", "TEMP"]
    @test Pipelines.get_node_outputs(node) == ["TEMP_rescaled"]

    Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled", "No")
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
        SELECT No, cbwd, TEMP_rescaled FROM rescaled;
        """
    )
    Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted", "No")
    df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
    @test df′.TEMP ≈ df.TEMP

    card = Pipelines.Card(d["zscore2"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled", "No")
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
        SELECT No, TEMP_rescaled AS PRES_rescaled_hat FROM rescaled;
        """
    )

    Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted", "No")
    df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
    @test df′.PRES_hat ≈ @. PRES_mean + df.TEMP_rescaled * PRES_std

    card = Pipelines.Card(d["maxabs"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled", "No")
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
        SELECT No, year, month, cbwd, TEMP_rescaled FROM rescaled;
        """
    )
    Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted", "No")
    df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
    @test df′.TEMP ≈ df.TEMP

    card = Pipelines.Card(d["minmax"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled", "No")
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
        SELECT No, TEMP_rescaled FROM rescaled;
        """
    )
    Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted", "No")
    df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
    @test df′.TEMP ≈ df.TEMP

    card = Pipelines.Card(d["log"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled", "No")
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
        SELECT No, PRES_rescaled FROM rescaled;
        """
    )
    Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted", "No")
    df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
    @test df′.PRES ≈ df.PRES

    card = Pipelines.Card(d["logistic"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "rescaled", "No")
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
        SELECT No, hour_rescaled FROM rescaled;
        """
    )
    Pipelines.evaljoin(repo, invert(node), "tbl" => "inverted", "No")
    df′ = DBInterface.execute(DataFrame, repo, "FROM inverted")
    @test df′.hour ≈ df.hour
end

@testset "cluster" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cluster.json"))

    # 200-row table shared by the O(N²) methods and the option variants
    DBInterface.execute(
        Returns(nothing), repo,
        "CREATE OR REPLACE TABLE cl_small AS (FROM selection LIMIT 200)",
    )
    smalldf = DBInterface.execute(DataFrame, repo, "FROM cl_small ORDER BY No")
    Xsmall = permutedims([smalldf.TEMP smalldf.PRES])

    # hand-computed predict expectations: every method assigns each column
    # of X to the nearest of the fitted columns C under its metric (ties to
    # the earliest-fitted, matching argmin); dbscan additionally requires
    # the winner within `radius`, else noise 0
    sqeuclid(u, v) = sum(abs2, u .- v)
    euclid(u, v) = sqrt(sum(abs2, u .- v))
    cityblock(u, v) = sum(abs.(u .- v))
    chebyshev(u, v) = maximum(abs.(u .- v))
    nearest_center(X, C, dist) =
        [argmin([dist(X[:, j], C[:, k]) for k in axes(C, 2)]) for j in axes(X, 2)]
    nearest_core(X, cores, labels, radius, dist) = [
        begin
            ds = [dist(X[:, j], cores[:, k]) for k in axes(cores, 2)]
            k = isempty(ds) ? 0 : argmin(ds)
            (k != 0 && ds[k] <= radius) ? labels[k] : 0
        end
            for j in axes(X, 2)
    ]
    fitted(node) = Pipelines.jlddeserialize(get_state(node).content)

    @testset "kmeans" begin
        card = Pipelines.Card(d["kmeans"])
        @test !Pipelines.invertible(card)

        node = Node(card)
        @test Pipelines.get_node_inputs(node) == ["TEMP", "PRES", "Iws"]
        @test Pipelines.get_node_outputs(node) == ["cluster"]

        Pipelines.train_evaljoin!(repo, node, "selection" => "clustering", "No")
        df = DBInterface.execute(DataFrame, repo, "FROM clustering")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "cluster",
        ]

        # reference fit with every option of the JSON card spelled out
        train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
        R = kmeans(
            [train_df.TEMP train_df.PRES train_df.Iws]', 3;
            maxiter = 100, tol = 1.0e-6, rng = StreamlinerCore.get_rng(1234),
            weights = train_df.Iws, init = :kmpp, distance = Pipelines.SqEuclidean(),
        )
        @test assignments(R) == df.cluster

        # k-means predict through the partition split: fit on partition 1, assign ALL rows.
        # This is what `predict` unlocks — before, held-out (partition 2) rows were unassigned.
        DBInterface.execute(
            Returns(nothing), repo,
            "CREATE OR REPLACE TABLE parted AS \
             SELECT *, CASE WHEN No % 4 = 0 THEN 2 ELSE 1 END AS partition FROM selection"
        )

        pnode = Node(Pipelines.Card(merge(d["kmeans"], Dict("partition" => "partition"))))
        Pipelines.train_evaljoin!(repo, pnode, "parted" => "pclust", "No")
        pdf = DBInterface.execute(DataFrame, repo, "FROM pclust ORDER BY No")
        @test all(∈(1:3), pdf.cluster)   # every row assigned, partition-2 rows included

        # reference centroids fit on partition 1 only (same config as the
        # card, restricted to partition 1); every row → its nearest centroid
        p1 = DBInterface.execute(DataFrame, repo, "FROM parted WHERE partition = 1")
        R1 = kmeans(
            [p1.TEMP p1.PRES p1.Iws]', 3;
            maxiter = 100, tol = 1.0e-6, rng = StreamlinerCore.get_rng(1234),
            weights = p1.Iws, init = :kmpp, distance = Pipelines.SqEuclidean(),
        )
        allrows = DBInterface.execute(DataFrame, repo, "FROM parted ORDER BY No")
        Xa = permutedims([allrows.TEMP allrows.PRES allrows.Iws])
        @test pdf.cluster == nearest_center(Xa, R1.centers, sqeuclid)

        # `assign_inputs` (the kmeansAssign config differs from kmeans only
        # by it): same partition-1 fit, assign on [TEMP, PRES] only
        anode = Node(Pipelines.Card(merge(d["kmeansAssign"], Dict("partition" => "partition"))))
        Pipelines.train_evaljoin!(repo, anode, "parted" => "aclust", "No")
        adf = DBInterface.execute(DataFrame, repo, "FROM aclust ORDER BY No")
        Xs = permutedims([allrows.TEMP allrows.PRES])
        @test adf.cluster == nearest_center(Xs, R1.centers[1:2, :], sqeuclid)

        # options: seeding enum + metric by registry name, fit and predict
        # under the SAME metric (inline card: the JSON base carries weights
        # and a third input that this variant deliberately drops)
        kvnode = Node(Pipelines.Card(Dict(
            "type" => "cluster", "method" => "kmeans", "inputs" => ["TEMP", "PRES"],
            "output" => "kvcluster",
            "method_options" => Dict(
                "classes" => 3, "seed" => 1234, "init" => "rand", "metric" => "cityblock",
            ),
        )))
        Pipelines.train_evaljoin!(repo, kvnode, "cl_small" => "kv_clust", "No")
        kvst = fitted(kvnode)
        @test size(kvst.centers, 2) == 3
        kvdf = DBInterface.execute(DataFrame, repo, "FROM kv_clust ORDER BY No")
        @test kvdf.kvcluster == nearest_center(Xsmall, kvst.centers, cityblock)
    end

    @testset "dbscan" begin
        card = Pipelines.Card(d["dbscan"])
        @test !Pipelines.invertible(card)

        node = Node(card)
        @test Pipelines.get_node_inputs(node) == ["TEMP", "PRES"]
        @test Pipelines.get_node_outputs(node) == ["dbcluster"]

        Pipelines.train_evaljoin!(repo, node, "selection" => "clustering", "No")
        df = DBInterface.execute(DataFrame, repo, "FROM clustering")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "dbcluster",
        ]

        train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
        R = dbscan([train_df.TEMP train_df.PRES]', 0.02)
        @test assignments(R) == df.dbcluster

        # predict: the nearest fitted core point within `radius` labels rows
        # out of sample (DBSCAN's own border rule); no core in reach → noise
        st = fitted(node)
        @test st.label == assignments(R)
        probes = DataFrame(
            "No" => [1, 2],
            "TEMP" => [st.core_points[1, 1], 999.0],
            "PRES" => [st.core_points[2, 1], 999.0],
        )
        DuckDBUtils.load_table(repo, probes, "dbprobes")
        Pipelines.evaljoin(repo, node, "dbprobes" => "dbprobes_out", "No")
        pdf = DBInterface.execute(DataFrame, repo, "FROM dbprobes_out ORDER BY No")
        @test pdf.dbcluster == [st.core_label[1], 0]

        # `assign_inputs`: same fit, but assign on TEMP only
        anode = Node(Pipelines.Card(merge(d["dbscan"], Dict("assign_inputs" => ["TEMP"]))))
        Pipelines.train_evaljoin!(repo, anode, "selection" => "dbclust_temp", "No")
        ast = fitted(anode)
        adf = DBInterface.execute(DataFrame, repo, "FROM dbclust_temp ORDER BY No")
        sel = DBInterface.execute(DataFrame, repo, "FROM selection ORDER BY No")
        Xtemp = permutedims(sel.TEMP)
        @test adf.dbcluster == nearest_core(Xtemp, ast.core_points[1:1, :], ast.core_label, ast.radius, euclid)

        # options: metric drives fit and nearest-core predict together;
        # non-true metrics are refused (the KD-trees need the triangle inequality)
        dcnode = Node(Pipelines.Card(merge(d["dbscan"], Dict(
            "method_options" => Dict("radius" => 0.02, "metric" => "cityblock"),
            "output" => "dbcb",
        ))))
        Pipelines.train_evaljoin!(repo, dcnode, "cl_small" => "db_cb", "No")
        dcst = fitted(dcnode)
        dcdf = DBInterface.execute(DataFrame, repo, "FROM db_cb ORDER BY No")
        @test dcdf.dbcb == nearest_core(Xsmall, dcst.core_points, dcst.core_label, dcst.radius, cityblock)
        dbad = Node(Pipelines.Card(merge(d["dbscan"], Dict(
            "method_options" => Dict("radius" => 0.02, "metric" => "sqeuclidean"),
        ))))
        @test_throws ArgumentError Pipelines.train_evaljoin!(repo, dbad, "cl_small" => "db_bad", "No")
    end

    @testset "affinity propagation" begin
        # exemplars are fitted points, assignment is nearest exemplar (the
        # method's own rule; Clustering.jl ships no predict — see
        # JuliaStats/Clustering.jl#63); O(N²) fit, hence the small table
        apnode = Node(Pipelines.Card(d["affinity"]))
        Pipelines.train_evaljoin!(repo, apnode, "cl_small" => "ap_clust", "No")
        apst = fitted(apnode)
        K = size(apst.centers, 2)
        @test K >= 2
        apdf = DBInterface.execute(DataFrame, repo, "FROM ap_clust ORDER BY No")
        @test apdf.apcluster == nearest_center(Xsmall, apst.centers, sqeuclid)

        # the preference knob's direction: preference 0 (≥ every pairwise
        # similarity) splits down to roughly one exemplar per distinct point —
        # far more than the median default. Exact counts and the converged
        # flag are data traits, not invariants: this dataset's duplicate
        # (TEMP, PRES) rows make the messages oscillate at default damping
        # (converged stays false in the state, and the card warns), without
        # perturbing the exemplar set the assertions above validate.
        @test apst.converged isa Bool
        @test K < 200
        fnode = Node(Pipelines.Card(d["affinityPreferenceZero"]))
        Pipelines.train_evaljoin!(repo, fnode, "cl_small" => "ap_all", "No")
        @test size(fitted(fnode).centers, 2) > K

        # exemplars label themselves; far rows are still assigned (nearest
        # exemplar has no noise channel)
        approbes = DataFrame(
            "No" => [1, 2],
            "TEMP" => [apst.centers[1, 1], 999.0],
            "PRES" => [apst.centers[2, 1], 999.0],
        )
        DuckDBUtils.load_table(repo, approbes, "approbes")
        Pipelines.evaljoin(repo, apnode, "approbes" => "approbes_out", "No")
        apo = DBInterface.execute(DataFrame, repo, "FROM approbes_out ORDER BY No")
        @test apo.apcluster[1] == 1
        @test apo.apcluster[2] in 1:K

        # preference_rule: the resolved preference is kept in the state —
        # exact plumbing check, convergence-independent
        svals = vec([-sqeuclid(Xsmall[:, i], Xsmall[:, j]) for i in axes(Xsmall, 2), j in axes(Xsmall, 2)])
        @test apst.preference ≈ median(svals)
        mnode = Node(Pipelines.Card(merge(d["affinity"], Dict(
            "method_options" => Dict("preference_rule" => "min"),
        ))))
        Pipelines.train_evaljoin!(repo, mnode, "cl_small" => "ap_min", "No")
        @test fitted(mnode).preference ≈ minimum(svals)
    end

    @testset "kmedoids" begin
        # medoids are fitted points; assignment is nearest medoid under the
        # card's metric (the CLUSTER_METRICS registry)
        kmnode = Node(Pipelines.Card(d["kmedoids"]))
        Pipelines.train_evaljoin!(repo, kmnode, "cl_small" => "km_clust", "No")
        kmst = fitted(kmnode)
        @test size(kmst.centers, 2) == 3
        @test kmst.converged isa Bool
        @test all(k -> any(j -> kmst.centers[:, k] == Xsmall[:, j], axes(Xsmall, 2)), axes(kmst.centers, 2))
        kmdf = DBInterface.execute(DataFrame, repo, "FROM km_clust ORDER BY No")
        @test kmdf.kmcluster == nearest_center(Xsmall, kmst.centers, sqeuclid)

        # the chosen metric drives both the fit and the assignment
        chnode = Node(Pipelines.Card(d["kmedoidsChebyshev"]))
        Pipelines.train_evaljoin!(repo, chnode, "cl_small" => "km_cheb", "No")
        chst = fitted(chnode)
        chdf = DBInterface.execute(DataFrame, repo, "FROM km_cheb ORDER BY No")
        @test chdf.kmcluster == nearest_center(Xsmall, chst.centers, chebyshev)

        # seeding enum mirrored from kmeans
        krnode = Node(Pipelines.Card(merge(d["kmedoids"], Dict(
            "method_options" => Dict("classes" => 3, "seed" => 1234, "init" => "rand"),
        ))))
        Pipelines.train_evaljoin!(repo, krnode, "cl_small" => "km_rand", "No")
        krst = fitted(krnode)
        @test size(krst.centers, 2) == 3
        @test all(k -> any(j -> krst.centers[:, k] == Xsmall[:, j], axes(Xsmall, 2)), axes(krst.centers, 2))

        # the registry is open to plain functions, e.g. halving TEMP's
        # weight. finally (without catch) swallows nothing: it only
        # guarantees the test-only entry leaves the global registry, so a
        # failure here cannot contaminate later testsets.
        halftemp(u, v) = abs(u[1] - v[1]) / 2 + abs(u[2] - v[2])
        Pipelines.CLUSTER_METRICS["halftemp"] = _ -> halftemp
        try
            hd = merge(d["kmedoids"], Dict(
                "method_options" => Dict("classes" => 3, "seed" => 1234, "metric" => "halftemp"),
            ))
            hnode = Node(Pipelines.Card(hd))
            Pipelines.train_evaljoin!(repo, hnode, "cl_small" => "km_half", "No")
            hst = fitted(hnode)
            hdf = DBInterface.execute(DataFrame, repo, "FROM km_half ORDER BY No")
            @test hdf.kmcluster == nearest_center(Xsmall, hst.centers, halftemp)
            # a custom metric defines its own use of the inputs: assign_inputs is refused
            bad = Node(Pipelines.Card(merge(hd, Dict("assign_inputs" => ["TEMP"]))))
            @test_throws ArgumentError Pipelines.train_evaljoin!(repo, bad, "cl_small" => "km_bad", "No")
            # kmeans requires a Distances.jl semimetric: plain functions refused
            kbad = Node(Pipelines.Card(Dict(
                "type" => "cluster", "method" => "kmeans", "inputs" => ["TEMP", "PRES"],
                "output" => "kvcluster",
                "method_options" => Dict("classes" => 3, "seed" => 1234, "metric" => "halftemp"),
            )))
            @test_throws ArgumentError Pipelines.train_evaljoin!(repo, kbad, "cl_small" => "kv_bad", "No")
        finally
            delete!(Pipelines.CLUSTER_METRICS, "halftemp")
        end
    end
end

@testset "dimensionality reduction" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "dimensionality_reduction.json"))

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
    Pipelines.train_evaljoin!(repo, part_node, "small" => "partition", "No")

    card = Pipelines.Card(d["pca"])
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["DEWP", "TEMP", "PRES", "partition"]
    @test Pipelines.get_node_outputs(node) == ["component_1", "component_2"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "dimres", "No")
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

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["DEWP", "TEMP", "PRES", "partition"]
    @test Pipelines.get_node_outputs(node) == ["component_1", "component_2"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "dimres", "No")
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

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["DEWP", "TEMP", "PRES", "partition"]
    @test Pipelines.get_node_outputs(node) == ["component_1", "component_2"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "dimres", "No")
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

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["DEWP", "TEMP", "PRES", "partition"]
    @test Pipelines.get_node_outputs(node) == ["component_1", "component_2"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "dimres", "No")
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
    Pipelines.train_evaljoin!(repo, part_node, "selection" => "partition", "No")

    card = Pipelines.Card(d["hasPartition"])
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["cbwd", "year", "No", "TEMP", "partition"]
    @test Pipelines.get_node_outputs(node) == ["TEMP_hat"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "glm", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM glm")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat",
    ]
    train_df = DBInterface.execute(DataFrame, repo, "FROM partition WHERE partition = 1")
    m = lm(@formula(TEMP ~ 1 + cbwd * year + No), train_df)
    @test predict(m, df) == df.TEMP_hat

    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))

    card = Pipelines.Card(d["hasWeights"])

    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "partition" => "glm", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM glm")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "PRES_hat",
    ]
    train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
    weights = fweights(train_df.Iws)
    m = glm(@formula(PRES ~ 1 + cbwd * year + No), train_df, Gamma(); weights)
    @test predict(m, df) == df.PRES_hat

    card = Pipelines.Card(d["isMixed"])

    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "partition" => "mixed_model", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM mixed_model")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat",
    ]
    train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
    m = lmm(@formula(TEMP ~ 1 + year + 1 | cbwd), train_df)
    @test predict(m, df) == df.TEMP_hat

    card = Pipelines.Card(d["isMixedHasWeights"])

    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "partition" => "mixed_model", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM mixed_model")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition", "TEMP_hat",
    ]
    train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
    weights = train_df.Iws
    m = lmm(@formula(TEMP ~ 1 + year + 1 | cbwd), train_df; weights)
    @test predict(m, df) == df.TEMP_hat
end

@testset "interp" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "interp.json"))

    part_card = Pipelines.Card(d["partition"])
    part_node = Node(part_card)
    Pipelines.train_evaljoin!(repo, part_node, "selection" => "partition", "No")

    card = Pipelines.Card(d["constant"])
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["No", "TEMP", "PRES", "partition"]
    @test Pipelines.get_node_outputs(node) == ["TEMP_hat", "PRES_hat"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "interp", "No")
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

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["No", "TEMP", "PRES", "partition"]
    @test Pipelines.get_node_outputs(node) == ["TEMP_hat", "PRES_hat"]

    Pipelines.train_evaljoin!(repo, node, "partition" => "interp", "No")
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
            "n_components" => 3,
            "method_options" => Dict("max" => 365.0),
            "lambda" => 0.5,
            "suffix" => "gaussian"
        )

        for (k, v) in pairs(Pipelines.TEMPORAL_PREPROCESSING_METHODS)
            c = merge(base_fields, Dict("method" => k))
            card = GaussianEncodingCard(c)
            _max = base_fields["method_options"]["max"]
            @test card.temporal_preprocessor == v(_max)
        end

        invalid_method = "nonexistent_method"
        invalid_config = merge(base_fields, Dict("method" => invalid_method))
        @test_throws ArgumentError GaussianEncodingCard(invalid_config)

        invalid_config = Dict(
            "type" => "gaussian_encoding",
            "input" => "date",
            "n_components" => 0,
            "max" => 365.0,
            "lambda" => 0.5,
            "method" => "identity"
        )
        @test_throws ArgumentError GaussianEncodingCard(invalid_config)
    end

    function gauss_train_test(node::Node)
        card, state = get_card(node), get_state(node)
        expected_means = range(0, step = 1 / card.n_components, length = card.n_components)
        expected_sigma = step(expected_means) * card.lambda
        expected_d = card.temporal_preprocessor.max
        expected_keys = vcat(["μ_$i" for i in 1:card.n_components], ["σ", "d"])

        params = Pipelines.jlddeserialize(state.content)
        @test isempty(setdiff(expected_keys, keys(params)))
        @test all([params["μ_$i"] == [v] for (i, v) in enumerate(expected_means)])
        @test params["σ"][1] ≈ expected_sigma
        @test params["d"][1] ≈ expected_d
    end

    _rem(x) = rem(x, 1, RoundNearest)
    function gauss_evaluate_test(result, node::Node, origin; processing)
        card = get_card(node)
        @test names(result) == union(names(origin), Pipelines.get_node_outputs(node))

        origin_column = origin[:, card.input]
        max_value = card.temporal_preprocessor.max
        preprocessed_values = processing.(origin_column)
        μs = range(0, step = 1 / card.n_components, length = card.n_components)
        σ = step(μs) * card.lambda
        for (i, μ) in enumerate(μs)
            expected_values = pdf.(Normal(0, σ), _rem.(preprocessed_values ./ max_value .- μ)) .* σ
            @test result[:, "$(card.input)_gaussian_$i"] ≈ expected_values
        end
    end

    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    card = Pipelines.Card(d["identity"])
    node = Node(card)
    @test !Pipelines.invertible(node)
    Pipelines.train_evaljoin!(repo, node, "origin" => "encoded", "No")
    gauss_train_test(node)
    result = DBInterface.execute(DataFrame, repo, "FROM encoded")
    gauss_evaluate_test(result, node, origin; processing = identity)
    @test Pipelines.get_node_outputs(node) == [
        "month_gaussian_1",
        "month_gaussian_2",
        "month_gaussian_3",
        "month_gaussian_4",
    ]
    @test Pipelines.get_node_inputs(node) == ["month"]

    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    card = Pipelines.Card(d["dayofweek"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "origin" => "encoded", "No")
    gauss_train_test(node)
    result = DBInterface.execute(DataFrame, repo, "FROM encoded")
    gauss_evaluate_test(result, node, origin; processing = x -> dayofweek(x) % 7) # SQL starts from Sunday = 0
    @test Pipelines.get_node_outputs(node) == ["date_gaussian_1", "date_gaussian_2", "date_gaussian_3"]
    @test Pipelines.get_node_inputs(node) == ["date"]

    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    card = Pipelines.Card(d["dayofyear"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "origin" => "encoded", "No")
    gauss_train_test(node)
    result = DBInterface.execute(DataFrame, repo, "FROM encoded")
    gauss_evaluate_test(result, node, origin; processing = dayofyear)
    @test Pipelines.get_node_outputs(node) == [
        "date_gaussian_1", "date_gaussian_2", "date_gaussian_3", "date_gaussian_4",
        "date_gaussian_5", "date_gaussian_6", "date_gaussian_7", "date_gaussian_8",
        "date_gaussian_9", "date_gaussian_10", "date_gaussian_11", "date_gaussian_12",
    ]
    @test Pipelines.get_node_inputs(node) == ["date"]

    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    card = Pipelines.Card(d["hour"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "origin" => "encoded", "No")
    gauss_train_test(node)
    result = DBInterface.execute(DataFrame, repo, "FROM encoded")
    gauss_evaluate_test(result, node, origin; processing = hour)
    @test Pipelines.get_node_outputs(node) == [
        "time_gaussian_1",
        "time_gaussian_2",
        "time_gaussian_3",
        "time_gaussian_4",
    ]
    @test only(Pipelines.get_node_inputs(node)) == "time"

    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    card = Pipelines.Card(d["minute"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "origin" => "encoded", "No")
    gauss_train_test(node)
    result = DBInterface.execute(DataFrame, repo, "FROM encoded")
    gauss_evaluate_test(result, node, origin; processing = minute)
    @test Pipelines.get_node_outputs(node) == ["time_gaussian_1"]
    @test only(Pipelines.get_node_inputs(node)) == "time"
end

@testset "streamliner" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "streamliner.json"))

    part_card = Pipelines.Card(d["partition"])
    part_node = Node(part_card)
    Pipelines.train_evaljoin!(repo, part_node, "selection" => "partition", "No")

    model_dir = joinpath(@__DIR__, "static", "model")
    training_dir = joinpath(@__DIR__, "static", "training")

    card = @with(
        Pipelines.PARSER => Pipelines.default_parser(),
        Pipelines.MODEL_DIR => model_dir,
        Pipelines.TRAINING_DIR => training_dir,
        Pipelines.Card(d["basic"])
    )
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["No", "TEMP", "PRES", "Iws", "partition"]
    @test Pipelines.get_node_outputs(node) == ["Iws_hat"]

    Pipelines.train!(repo, node, "partition", "No")
    state = get_state(node)
    res = state.metadata
    @test res["iteration"] == 4
    @test !res["resumed"]
    @test length(res["stats"][1]) == length(res["stats"][2]) == 2
    @test res["successful"]
    @test res["trained"]

    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "partition" => "prediction", "No")
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
        Pipelines.MODEL_DIR => model_dir,
        Pipelines.TRAINING_DIR => training_dir,
        Pipelines.Card(d["classifier"])
    )
    @test !Pipelines.invertible(card)

    node = Node(card)
    Pipelines.train!(repo, node, "partition", "No")
    state = get_state(node)
    res = state.metadata
    @test res["iteration"] == 4
    @test !res["resumed"]
    @test length(res["stats"][1]) == length(res["stats"][2]) == 2
    @test res["successful"]
    @test res["trained"]

    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "partition" => "prediction", "No")
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
