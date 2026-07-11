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

    train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
    rng = StreamlinerCore.get_rng(1234)
    weights = train_df.Iws
    R = kmeans([train_df.TEMP train_df.PRES train_df.Iws]', 3; maxiter = 100, tol = 1.0e-6, rng, weights)
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

    # reference centroids fit on partition 1 only; every row → its nearest centroid
    p1 = DBInterface.execute(DataFrame, repo, "FROM parted WHERE partition = 1")
    R1 = kmeans(
        [p1.TEMP p1.PRES p1.Iws]', 3;
        maxiter = 100, tol = 1.0e-6, rng = StreamlinerCore.get_rng(1234), weights = p1.Iws
    )
    allrows = DBInterface.execute(DataFrame, repo, "FROM parted ORDER BY No")
    Xa = permutedims([allrows.TEMP allrows.PRES allrows.Iws])
    exp_full = [argmin(vec(sum(abs2, Xa[:, j] .- R1.centers; dims = 1))) for j in axes(Xa, 2)]
    @test pdf.cluster == exp_full

    # `assign_inputs`: same partition-1 fit, but assign on [TEMP, PRES] only (drop Iws)
    anode = Node(Pipelines.Card(merge(d["kmeansAssign"], Dict("partition" => "partition"))))
    Pipelines.train_evaljoin!(repo, anode, "parted" => "aclust", "No")
    adf = DBInterface.execute(DataFrame, repo, "FROM aclust ORDER BY No")
    Xs = permutedims([allrows.TEMP allrows.PRES])
    exp_sub = [argmin(vec(sum(abs2, Xs[:, j] .- R1.centers[1:2, :]; dims = 1))) for j in axes(Xs, 2)]
    @test adf.cluster == exp_sub

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

    # dbscan predict: the nearest fitted core point within `radius` labels
    # rows out of sample (DBSCAN's own border rule); no core in reach → noise
    st = Pipelines.jlddeserialize(get_state(node).content)
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
    ast = Pipelines.jlddeserialize(get_state(anode).content)
    adf = DBInterface.execute(DataFrame, repo, "FROM dbclust_temp ORDER BY No")
    sel = DBInterface.execute(DataFrame, repo, "FROM selection ORDER BY No")
    exp_temp = [
        begin
            ds = abs.(sel.TEMP[j] .- ast.core_points[1, :])
            k = argmin(ds)
            ds[k] <= ast.radius ? ast.core_label[k] : 0
        end
            for j in eachindex(sel.TEMP)
    ]
    @test adf.dbcluster == exp_temp

    # affinity propagation: exemplars are fitted points, assignment is
    # nearest exemplar (the method's own rule; Clustering.jl ships no
    # predict — see JuliaStats/Clustering.jl#63). O(N²) fit, so a small table.
    DBInterface.execute(
        Returns(nothing), repo,
        "CREATE OR REPLACE TABLE ap_small AS (FROM selection LIMIT 200)",
    )
    apnode = Node(Pipelines.Card(d["affinity"]))
    Pipelines.train_evaljoin!(repo, apnode, "ap_small" => "ap_clust", "No")
    apst = Pipelines.jlddeserialize(get_state(apnode).content)
    K = size(apst.centers, 2)
    @test K >= 2
    apdf = DBInterface.execute(DataFrame, repo, "FROM ap_clust ORDER BY No")
    smalldf = DBInterface.execute(DataFrame, repo, "FROM ap_small ORDER BY No")
    Xap = permutedims([smalldf.TEMP smalldf.PRES])
    exp_ap = [argmin(vec(sum(abs2, Xap[:, j] .- apst.centers; dims = 1))) for j in axes(Xap, 2)]
    @test apdf.apcluster == exp_ap

    # the preference knob's direction: preference 0 (≥ every pairwise
    # similarity) splits down to roughly one exemplar per distinct point —
    # far more than the median default. Exact counts and the converged flag
    # are data traits, not invariants: this dataset's duplicate (TEMP, PRES)
    # rows make the messages oscillate at default damping (converged stays
    # false in the state, and the card warns), without perturbing the
    # exemplar set the assertions above validate.
    @test apst.converged isa Bool
    @test K < 200
    fnode = Node(Pipelines.Card(d["affinityAll"]))
    Pipelines.train_evaljoin!(repo, fnode, "ap_small" => "ap_all", "No")
    fst = Pipelines.jlddeserialize(get_state(fnode).content)
    @test size(fst.centers, 2) > K

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
