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
        "PRES", "cbwd", "Iws", "Is", "Ir", "_tiled_partition",
    ]
    @test count(==(1), df._tiled_partition) == 29218
    @test count(==(2), df._tiled_partition) == 14606

    # test repeating strategy
    card = Pipelines.Card(d["tiles2"])
    str, _ = DuckDBUtils.render_params(
        DuckDBUtils.get_catalog(repo),
        Partition() |> Select(card.output => Pipelines.get_sql(card.method))
    )
    @test str == "SELECT list_extract(list_value(1, 1, 2), \
        ((((ntile(7) OVER ()) - 1) % 3) + 1)) AS \"_tiled_partition\""
    node = Node(card)

    Pipelines.train_evaljoin!(repo, node, "selection" => "split", "No")
    v1 = DBInterface.execute(DataFrame, repo, "FROM split")._tiled_partition

    card = Pipelines.Card(d["tiles3"])
    str, _ = DuckDBUtils.render_params(
        DuckDBUtils.get_catalog(repo),
        Partition() |> Select(card.output => Pipelines.get_sql(card.method))
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "_percentile_partition",
    ]
    @test count(==(1), df._percentile_partition) == 39441
    @test count(==(2), df._percentile_partition) == 4383
    # TODO: port TimeFunnelUtils tests
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "_row_number",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "_percent_rank",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "_rank",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "TEMP_rescaled",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "TEMP_rescaled", "PRES_rescaled",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "TEMP_rescaled",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "TEMP_rescaled",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "PRES_rescaled",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "hour_rescaled",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "cluster",
    ]

    train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
    rng = StreamlinerCore.get_rng(1234)
    weights = train_df.Iws
    R = kmeans([train_df.TEMP train_df.PRES train_df.Iws]', 3; maxiter = 100, tol = 1.0e-6, rng, weights)
    @test assignments(R) == df.cluster

    # the configured dissimilarity reaches the fit
    card = Pipelines.Card(d["kmeansCityblock"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "clustering", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM clustering")
    train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
    rng = StreamlinerCore.get_rng(1234)
    R = kmeans(
        [train_df.TEMP train_df.PRES]', 3;
        maxiter = 100, tol = 1.0e-6, rng, distance = Pipelines.Cityblock(),
    )
    @test assignments(R) == df.cbcluster

    # the configured seeding reaches the fit
    card = Pipelines.Card(d["kmeansInit"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "clustering", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM clustering")
    train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
    rng = StreamlinerCore.get_rng(1234)
    R = kmeans(
        [train_df.TEMP train_df.PRES train_df.Iws]', 3;
        maxiter = 100, tol = 1.0e-6, rng, weights = train_df.Iws, init = :rand,
    )
    @test assignments(R) == df.initcluster

    card = Pipelines.Card(d["dbscan"])
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["TEMP", "PRES"]
    @test Pipelines.get_node_outputs(node) == ["dbcluster"]

    Pipelines.train_evaljoin!(repo, node, "selection" => "clustering", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM clustering")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "dbcluster",
    ]

    train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
    R = dbscan([train_df.TEMP train_df.PRES]', 0.02)
    @test assignments(R) == df.dbcluster

    # the configured metric reaches the dbscan fit
    card = Pipelines.Card(d["dbscanCityblock"])
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "clustering", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM clustering")
    train_df = DBInterface.execute(DataFrame, repo, "FROM selection")
    R = dbscan([train_df.TEMP train_df.PRES]', 0.02; metric = Pipelines.Cityblock())
    @test assignments(R) == df.dbcbcluster

    # affinity propagation builds a dense N×N similarity matrix: test on a
    # small table, deduplicated so that the fit converges (identical points
    # receive identical messages and can keep oscillating)
    DBInterface.execute(
        Returns(nothing),
        repo,
        """
        CREATE OR REPLACE TABLE cl_small AS (
            SELECT min("No") AS "No", "TEMP", "PRES"
            FROM (FROM selection LIMIT 200)
            GROUP BY "TEMP", "PRES"
            ORDER BY "No"
        );
        """
    )
    card = Pipelines.Card(d["affinity"])
    @test !Pipelines.invertible(card)

    node = Node(card)
    @test Pipelines.get_node_inputs(node) == ["TEMP", "PRES"]
    @test Pipelines.get_node_outputs(node) == ["apcluster"]

    Pipelines.train_evaljoin!(repo, node, "cl_small" => "clustering", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM clustering")

    train_df = DBInterface.execute(DataFrame, repo, "FROM cl_small")
    X = [train_df.TEMP train_df.PRES]'
    S = -Pipelines.pairwise(Pipelines.SqEuclidean(), X, dims = 2)
    S[Pipelines.diagind(S)] .= vec(median(S, dims = 1))
    R = affinityprop(S; maxiter = 200, tol = 1.0e-6, damp = 0.5)
    @test R.converged
    @test df.apcluster == assignments(R)

    # the same fit WITHOUT the hand-deduplication: duplicates are collapsed
    # into count weights inside the method, so identical points no longer
    # keep the messages oscillating and every row still comes back labeled
    DBInterface.execute(
        Returns(nothing),
        repo,
        "CREATE OR REPLACE TABLE cl_dup AS (FROM selection LIMIT 200);"
    )
    counts = DBInterface.execute(
        DataFrame, repo,
        "SELECT count(*) AS n, count(DISTINCT (\"TEMP\", \"PRES\")) AS distinct_points FROM cl_dup"
    )
    @test counts.distinct_points[1] < counts.n[1]   # otherwise the test is vacuous

    node = Node(Pipelines.Card(d["affinity"]))
    Pipelines.train_evaljoin!(repo, node, "cl_dup" => "clustering_dup", "No")
    dup = DBInterface.execute(DataFrame, repo, "FROM clustering_dup")
    @test nrow(dup) == counts.n[1]
    @test all(>(0), dup.apcluster)
    # identical points must share a cluster
    per_point = DBInterface.execute(
        DataFrame, repo,
        "SELECT count(DISTINCT apcluster) AS k FROM clustering_dup GROUP BY \"TEMP\", \"PRES\""
    )
    @test all(==(1), per_point.k)
end

@testset "cluster reconciliation" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cluster.json"))

    # The matcher on hand-written fits. Density refits can only grow clusters
    # (an added point never separates two others), so the split, merge and
    # threshold branches are exercised here directly.
    relabel = Pipelines._relabel_map

    # an identical refit: every cluster keeps its label, noise stays noise
    m, highest = relabel([1, 1, 2, 2, 0], [1, 1, 2, 2, 0], 0.5, 2)
    @test m == Dict(0 => 0, 1 => 1, 2 => 2)
    @test highest == 2

    # inheritance follows membership, not the refit's numbering
    m, _ = relabel([2, 2, 1, 1], [1, 1, 2, 2], 0.5, 2)
    @test m[2] == 1 && m[1] == 2

    # split: the larger piece keeps the label, the smaller is an emergence
    m, highest = relabel([1, 1, 1, 4, 4, 2, 2], [1, 1, 1, 1, 1, 2, 2], 0.5, 2)
    @test m[1] == 1 && m[4] == 3 && m[2] == 2
    @test highest == 3

    # merge: the union inherits from its largest contributor (ties to the lowest)
    m, _ = relabel([1, 1, 1, 1], [1, 1, 2, 2], 0.5, 2)
    @test m[1] == 1

    # rows the stored fit never saw cannot claim a label...
    m, _ = relabel([1, 1, 2, 2], [1, 1], 0.5, 2)
    @test m[1] == 1 && m[2] == 3

    # ...and fresh labels continue from the highest ever issued, not the
    # highest present, so a forgotten cluster's number is never reused
    m, highest = relabel([1, 1, 2, 2], [1, 1], 0.5, 7)
    @test m[2] == 8 && highest == 8

    # the threshold is the share of previously-labelled rows the winner holds
    @test relabel([3, 3, 3, 3], [1, 2, 2, 2], 0.5, 3)[1][3] == 2   # 3/4 suffices
    @test relabel([3, 3, 3, 3], [1, 2, 2, 2], 0.8, 3)[1][3] == 4   # 3/4 < 0.8

    # The shared refit-and-reconcile evaluation, on three tight well-separated
    # blobs plus a fourth far away to add later.
    blob(cx, cy, k) = DataFrame(
        id = k .+ (1:9),
        x = [cx + 0.1 * (i % 3) for i in 1:9],
        y = [cy + 0.1 * (i ÷ 3) for i in 1:9],
    )
    base = reduce(vcat, [blob(0.0, 0.0, 0), blob(10.0, 0.0, 100), blob(0.0, 10.0, 200)])
    grown = vcat(base, blob(30.0, 30.0, 300))
    DuckDBUtils.load_table(repo, base, "recon_base")
    DuckDBUtils.load_table(repo, grown, "recon_grown")

    reconcile_state(node) = Pipelines.jlddeserialize(Pipelines.get_state(node).content)

    node = Node(Pipelines.Card(d["reconcile"]))
    Pipelines.train_evaljoin!(repo, node, "recon_base" => "recon_out", "id")
    fitted = DBInterface.execute(DataFrame, repo, "FROM recon_out ORDER BY id").cluster
    @test sort(unique(fitted)) == [1, 2, 3]

    # refitting on unchanged data produces no transitions
    Pipelines.evaljoin(repo, node, "recon_base" => "recon_again", "id")
    again = DBInterface.execute(DataFrame, repo, "FROM recon_again ORDER BY id")
    @test again.cluster == fitted

    # a far-away blob is an emergence: one fresh label, old labels untouched
    Pipelines.evaljoin(repo, node, "recon_grown" => "recon_emerged", "id")
    emerged = DBInterface.execute(DataFrame, repo, "FROM recon_emerged ORDER BY id")
    @test emerged.cluster[emerged.id .< 300] == fitted
    @test unique(emerged.cluster[emerged.id .> 300]) == [maximum(fitted) + 1]
    # with lineage off both evaluations left the state alone
    @test reconcile_state(node).iteration == 1
    @test length(reconcile_state(node).members["label"]) == nrow(base)

    # lineage on: an evaluation that admits rows rolls the members forward,
    # stamping the iteration they arrived in
    node = Node(Pipelines.Card(merge(d["reconcile"], Dict("lineage" => true))))
    Pipelines.train_evaljoin!(repo, node, "recon_base" => "recon_out", "id")
    Pipelines.evaljoin(repo, node, "recon_grown" => "recon_emerged", "id")
    st = reconcile_state(node)
    @test st.iteration == 2
    @test length(st.members["label"]) == nrow(grown)
    @test sort(unique(st.members["iteration_origin"])) == [1, 2]

    # ...but one that admits nothing is a no-op: iterations measure growth,
    # so re-running an evaluation cannot age the members
    Pipelines.evaljoin(repo, node, "recon_grown" => "recon_noop", "id")
    @test reconcile_state(node).iteration == 2

    # memory keeps only the newest iterations, without reissuing freed labels
    node = Node(Pipelines.Card(merge(d["reconcile"], Dict("lineage" => true, "memory" => 1))))
    Pipelines.train_evaljoin!(repo, node, "recon_base" => "recon_out", "id")
    Pipelines.evaljoin(repo, node, "recon_grown" => "recon_emerged", "id")
    st = reconcile_state(node)
    @test unique(st.members["iteration_origin"]) == [2]
    @test length(st.members["label"]) == nrow(grown) - nrow(base)
    @test st.highest_label == maximum(fitted) + 1
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
        "PRES", "cbwd", "Iws", "Is", "Ir",
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
        "PRES", "cbwd", "Iws", "Is", "Ir",
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
        "PRES", "cbwd", "Iws", "Is", "Ir",
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
        "PRES", "cbwd", "Iws", "Is", "Ir",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "partition", "TEMP_hat",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "partition", "PRES_hat",
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
        "PRES", "cbwd", "Iws", "Is", "Ir", "partition", "TEMP_hat",
    ]
    train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
    m = lmm(@formula(TEMP ~ 1 + year + (1 | cbwd)), train_df)
    @test predict(m, df) == df.TEMP_hat

    card = Pipelines.Card(d["isMixedHasWeights"])

    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "partition" => "mixed_model", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM mixed_model")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "partition", "TEMP_hat",
    ]
    train_df = DBInterface.execute(DataFrame, repo, "FROM partition")
    weights = train_df.Iws
    m = lmm(@formula(TEMP ~ 1 + year + (1 | cbwd)), train_df; weights)
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
        "cbwd", "Iws", "Is", "Ir", "partition", "TEMP_hat", "PRES_hat",
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
        "cbwd", "Iws", "Is", "Ir", "partition", "TEMP_hat", "PRES_hat",
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
            "method" => Dict("type" => "", "max" => 365.0),
            "lambda" => 0.5,
            "suffix" => "gaussian"
        )

        for (k, v) in pairs(Pipelines.TEMPORAL_PREPROCESSING_METHODS)
            c = deepcopy(base_fields)
            c["method"]["type"] = k
            card = Card(c)
            _max = c["method"]["max"]
            @test card.method == v(_max)
        end

        invalid_method = "nonexistent_method"
        invalid_config = deepcopy(base_fields)
        invalid_config["method"]["type"] = invalid_method
        @test_throws ArgumentError Card(invalid_config)
    end

    function gauss_train_test(node::Node)
        card, state = get_card(node), get_state(node)
        expected_means = range(0, step = 1 / card.n_components, length = card.n_components)
        expected_sigma = step(expected_means) * card.lambda
        expected_d = card.method.max
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
        max_value = card.method.max
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
        "cbwd", "Iws", "Is", "Ir", "partition", "Iws_hat",
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
        "cbwd", "Iws", "Is", "Ir", "partition", "cbwd_hat",
    ]
    @test all(x -> x isa AbstractString, result.cbwd_hat)
    @test nrow(origin) == nrow(result)

    stats = Pipelines.report(repo, card, state)
    @test stats["training"]["accuracy"] ≈ 0.34 atol = 1.0e-2
    @test stats["validation"]["accuracy"] ≈ 0.36 atol = 1.0e-2
    @test stats["training"]["logitcrossentropy"] ≈ 2.82 atol = 1.0e-2
    @test stats["validation"]["logitcrossentropy"] ≈ 1.69 atol = 1.0e-2
end
