@testset "evaluation order" begin
    _train(wc, t, id; weights = nothing) = nothing
    function _evaluate(wc, model, t, id)
        return Pipelines.SimpleTable(k => zeros(length(id)) for k in wc.outputs), id
    end
    Pipelines.register_wild_card("trivial", "Trivial", _train, _evaluate)

    function trivialcard(inputs, outputs)
        c = Dict("type" => "trivial", "inputs" => inputs, "outputs" => outputs)
        return Pipelines.Card(c)
    end

    nodes = [
        Pipelines.Node(trivialcard(["temp"], ["pred humid"]), update = true),
        Pipelines.Node(trivialcard(["pred humid"], ["pred wind"]), update = true),
        Pipelines.Node(trivialcard(["wind", "wind name"], ["pred temp"]), update = true),
        Pipelines.Node(trivialcard(["wind"], ["wind name"]), update = true),
    ]

    g = Pipelines.digraph(nodes)
    order = Pipelines.topological_sort(g)
    @test order == [4, 8, 3, 7, 1, 5, 2, 6]

    repo = Repository()
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl1(temp DOUBLE)")
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl2(temp DOUBLE, wind DOUBLE)")
    DBInterface.execute(
        Returns(nothing), repo, """
        CREATE TABLE tbl3("temp" DOUBLE, "wind" DOUBLE, "pred humid" DOUBLE)
        """
    )
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl4(temp DOUBLE, wind DOUBLE)")

    @test_throws "wind" Pipelines.train_evaljoin!(repo, nodes, "tbl1")

    g, source_vars, output_vars = Pipelines.digraph_metadata(nodes)
    @test source_vars == ["temp", "wind"]
    @test output_vars == ["pred humid", "pred wind", "pred temp", "wind name"]

    faulty_node = Pipelines.Node(trivialcard(["temp"], ["pred temp"]))
    @test_throws ArgumentError Pipelines.digraph(vcat(nodes, [faulty_node]))

    # Test returned value of `Pipelines.train_evaljoin!`
    p = Pipelines.train_evaljoin!(repo, nodes, "tbl2")
    @test p.nodes === nodes
    @test collect(edges(p.g)) == collect(edges(Pipelines.digraph(nodes)))
    @test p.source_vars == ["temp", "wind"]
    @test p.output_vars == ["pred humid", "pred wind", "pred temp", "wind name"]

    nodes = [
        Pipelines.Node(trivialcard(["temp"], ["pred humid"]), update = false),
        Pipelines.Node(trivialcard(["pred humid"], ["pred wind"]), update = true),
        Pipelines.Node(trivialcard(["wind", "wind name"], ["pred temp"]), update = false),
        Pipelines.Node(trivialcard(["wind"], ["wind name"]), update = true),
    ]

    # Test returned value of `Pipelines.train_evaljoin!` when some update is not needed
    p = Pipelines.train_evaljoin!(repo, nodes, "tbl3")
    @test collect(edges(p.g)) == collect(edges(Pipelines.digraph(nodes)))
    @test p.source_vars == ["temp", "wind"]
    @test p.output_vars == ["pred humid", "pred wind", "pred temp", "wind name"]

    # original table must supply precomputed variabels
    @test_throws "pred humid" Pipelines.train_evaljoin!(repo, nodes, "tbl4")

    g = Pipelines.digraph(nodes)
    hs = Pipelines.compute_height(g, nodes)
    @test hs == [-1, 0, 1, 0]
    @test Pipelines.layers(hs) == [[2, 4], [3]]
    @test isempty(Pipelines.layers(Int[]))

    # Empty case
    @test Pipelines.digraph(Pipelines.Node[]) == DiGraph(0)

    nodes = [
        Pipelines.Node(trivialcard(["a", "c", "e"], ["f"]), update = false),
        Pipelines.Node(trivialcard(["a"], ["c", "d"]), update = true),
        Pipelines.Node(trivialcard(["b"], ["e"]), update = true),
        Pipelines.Node(trivialcard(["e", "f"], ["g", "h", "i"]), update = true),
    ]

    g, source_vars, output_vars = Pipelines.digraph_metadata(nodes)
    @test source_vars == ["a", "b"]
    @test nv(g) == 11
    # The graph nodes are
    # 1 => n1, 2 => n2, 3 => n3, 4 => n4,
    # 5 => "f", 6 => "c", 7 => "d", 8 => "e", 9 => "g", 10 => "h", 11 => "i".
    es = collect(edges(g))
    @test sort(es) == [
        Edge(1, 5),
        Edge(2, 6),
        Edge(2, 7),
        Edge(3, 8),
        Edge(4, 9),
        Edge(4, 10),
        Edge(4, 11),
        Edge(5, 4),
        Edge(6, 1),
        Edge(8, 1),
        Edge(8, 4),
    ]

    s = sprint(Pipelines.graphviz, g, nodes, output_vars)
    @test s == read(joinpath(@__DIR__, "static", "outputs", "graph.dot"), String)
end

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

    @testset "cards" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cards.json"))
        cards = Pipelines.Card.(d)
        nodes = Node.(cards)
        Pipelines.train_evaljoin!(repo, nodes, "selection")
        df = DBInterface.execute(DataFrame, repo, "FROM selection")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "_percentile_partition", "_tiled_partition",
            "PRES_rescaled", "TEMP_rescaled",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383

        Pipelines.evaljoin(repo, nodes, "source")
        df = DBInterface.execute(DataFrame, repo, "FROM source")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "_percentile_partition", "_tiled_partition",
            "PRES_rescaled", "TEMP_rescaled",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
    end

    @testset "nodes" begin
        d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "rescale.json"))

        _node = Node(Pipelines.Card(d["zscore"]))
        Pipelines.train!(repo, _node, "selection")
        card, state = get_card(_node), get_state(_node)

        node = Pipelines.Node(
            Dict(
                "card" => d["zscore"],
                "state" => Dict("content" => state.content, "metadata" => state.metadata)
            )
        )

        @test node.card isa Pipelines.RescaleCard
        for k in fieldnames(Pipelines.RescaleCard)
            @test getfield(node.card, k) == getfield(card, k)
        end
        @test node.state.content == state.content
        @test node.state.metadata == state.metadata
    end
end
