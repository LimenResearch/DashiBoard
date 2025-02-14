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
    spec = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "spec.json"))
    repo = Repository(joinpath(dir, "db.duckdb"))
    DataIngestion.load_files(repo, spec["data"]["files"])
    filters = DataIngestion.get_filter.(spec["filters"])
    DataIngestion.select(repo, filters)

    @testset "cards" begin
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "cards.json"))
        cards = Pipelines.get_card.(d)
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
        d = open(JSON3.read, joinpath(@__DIR__, "static", "configs", "rescale.json"))

        card = Pipelines.get_card(d["zscore"])
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
