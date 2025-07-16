@testset "evaluation order" begin
    _train(wc, t, id; weights = nothing) = nothing
    function _evaluate(wc, model, t, id)
        len = length(id)
        t_new = Pipelines.SimpleTable()
        for k in wc.outputs
            t_new[k] = zeros(len)
        end
        return t_new, id
    end
    Pipelines.register_wild_card("trivial", "Trivial", _train, _evaluate)

    function trivialcard(inputs, outputs)
        c = Dict("type" => "trivial", "inputs" => inputs, "outputs" => outputs)
        return Pipelines.Card(c)
    end

    nodes = [
        Pipelines.Node(trivialcard(["temp"], ["pred humid"]), true),
        Pipelines.Node(trivialcard(["pred humid"], ["pred wind"]), true),
        Pipelines.Node(trivialcard(["wind", "wind name"], ["pred temp"]), true),
        Pipelines.Node(trivialcard(["wind"], ["wind name"]), true),
    ]

    g = Pipelines.digraph(nodes, ["temp", "wind"])
    order = Pipelines.topological_sort(g)
    @test order == [4, 8, 3, 7, 1, 5, 2, 6]

    repo = Repository()
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl1(temp DOUBLE)")
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl2(temp DOUBLE, wind DOUBLE)")

    @test_throws KeyError Pipelines.evaluate!(repo, nodes, "tbl1")

    @test_throws KeyError Pipelines.digraph(nodes, ["temp"])
    @test_throws ArgumentError Pipelines.digraph(nodes, ["temp", "wind", "pred humid"])
    faulty_node = Pipelines.Node(trivialcard(["temp"], ["pred temp"]), true)
    @test_throws ArgumentError Pipelines.digraph(vcat(nodes, [faulty_node]), ["temp", "wind"])

    # Test returned value of `Pipelines.evaluate!`
    g, output_vars = Pipelines.evaluate!(repo, nodes, "tbl2")
    @test collect(edges(g)) == collect(edges(Pipelines.digraph(nodes, ["temp", "wind"])))
    @test output_vars == ["pred humid", "pred wind", "pred temp", "wind name"]

    nodes = [
        Pipelines.Node(trivialcard(["temp"], ["pred humid"]), false),
        Pipelines.Node(trivialcard(["pred humid"], ["pred wind"]), true),
        Pipelines.Node(trivialcard(["wind", "wind name"], ["pred temp"]), false),
        Pipelines.Node(trivialcard(["wind"], ["wind name"]), true),
    ]

    g = Pipelines.digraph(nodes, ["temp", "wind"])
    hs = Pipelines.compute_height(g, nodes)
    @test hs == [-1, 0, 1, 0]
    @test Pipelines.layers(hs) == [[2, 4], [3]]
    @test isempty(Pipelines.layers(Int[]))

    # Empty case
    @test Pipelines.digraph(Pipelines.Node[], String[]) == DiGraph(0)

    nodes = [
        Pipelines.Node(trivialcard(["a", "c", "e"], ["f"]), false),
        Pipelines.Node(trivialcard(["a"], ["c", "d"]), true),
        Pipelines.Node(trivialcard(["b"], ["e"]), true),
        Pipelines.Node(trivialcard(["e", "f"], ["g", "h", "i"]), true),
    ]
    table_vars = ["a", "b"]

    # TODO fix evaluation when some update is not required
    g, vars = Pipelines.digraph_metadata(nodes, table_vars)
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

    s = sprint(Pipelines.graphviz, g, nodes, vars)
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
        nodes = Pipelines.evaluate(repo, cards, "selection")
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

        Pipelines.evaluatenodes(repo, nodes, "source")
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

        card = Pipelines.Card(d["zscore"])
        state = Pipelines.evaluate(repo, card, "selection" => "rescaled")

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
