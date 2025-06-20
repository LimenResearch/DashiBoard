@testset "evaluation order" begin
    struct TrivialCard <: Pipelines.Card
        inputs::Vector{String}
        outputs::Vector{String}
    end
    Pipelines.inputs(t::TrivialCard) = OrderedSet(t.inputs)
    Pipelines.outputs(t::TrivialCard) = OrderedSet(t.outputs)
    function Pipelines.train(::Repository, ::TrivialCard, ::AbstractString; schema = nothing)
        return Pipelines.CardState()
    end
    function Pipelines.evaluate(
            ::Repository, ::TrivialCard, ::Pipelines.CardState, ::Pair;
            schema = nothing
        )
        return nothing
    end

    nodes = [
        Pipelines.Node(TrivialCard(["temp"], ["pred humid"]), true),
        Pipelines.Node(TrivialCard(["pred humid"], ["pred wind"]), true),
        Pipelines.Node(TrivialCard(["wind", "wind name"], ["pred temp"]), true),
        Pipelines.Node(TrivialCard(["wind"], ["wind name"]), true),
    ]

    g = Pipelines.digraph(nodes)
    order = Pipelines.topological_sort(g)
    @test order == [4, 3, 1, 2]

    nodes = [
        Pipelines.Node(TrivialCard(["temp"], ["pred humid"]), false),
        Pipelines.Node(TrivialCard(["pred humid"], ["pred wind"]), true),
        Pipelines.Node(TrivialCard(["wind", "wind name"], ["pred temp"]), false),
        Pipelines.Node(TrivialCard(["wind"], ["wind name"]), true),
    ]

    @test issetequal(Pipelines.required_inputs(nodes), ["temp", "wind"])

    repo = Repository()
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl1(temp DOUBLE)")
    DBInterface.execute(Returns(nothing), repo, "CREATE TABLE tbl2(temp DOUBLE, wind DOUBLE)")

    @test_throws ArgumentError Pipelines.evaluate!(repo, nodes, "tbl1")

    Pipelines.evaluate!(repo, nodes, "tbl2")
    updates = Pipelines.get_update.(nodes)
    @test updates == [false, true, true, true]
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
            "_tiled_partition", "PRES_rescaled", "TEMP_rescaled",
            "_percentile_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383

        Pipelines.evaluatenodes(repo, nodes, "source")
        df = DBInterface.execute(DataFrame, repo, "FROM source")
        @test issetequal(
            names(df), [
                "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
                "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
                "_tiled_partition", "PRES_rescaled", "TEMP_rescaled",
                "_percentile_partition",
            ]
        )
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
