@testset "groups" begin
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    c = Pipelines.Configuration(d["nodes"], d["groups"]) |> Pipelines.parse_deps!
    g, cols = Pipelines.dependency_graph(c)
    es = sort(collect(edges(g)))

    @test c.node_idxs == Dict(
        "rescale" => 1,
        "log" => 2,
        "pca" => 3,
        "partition" => 4,
    )
    @test c.node_configs[1]["card"]["group_by"].cols == ["cbwd"]
    @test c.node_configs[1]["card"]["inputs"][1].groups == ["weather"]
    @test c.node_configs[1]["card"]["inputs"][2].cols == ["No"]
    @test c.node_configs[1]["card"]["partition"].nodes == ["partition"]

    @test c.node_configs[2]["card"]["inputs"].cols == ["No"]

    @test c.node_configs[3]["card"]["inputs"][1].nodes == ["log"]
    @test c.node_configs[3]["card"]["inputs"][2].groups == ["weather"]
    @test c.node_configs[3]["card"]["inputs"][2].through == ["rescale"]

    @test c.node_configs[4]["card"]["order_by"].cols == ["No"]

    @test c.group_idxs == Dict("weather" => 1)
    @test c.group_configs[1].cols == ["PRES", "TEMP"]
    @test c.group_configs[1].through == String[]

    @test length(es) == 5
    @test Pair(es[1]) == (1 => 3)
    @test Pair(es[2]) == (2 => 3)
    @test Pair(es[3]) == (4 => 1)
    @test Pair(es[4]) == (5 => 1)
    @test Pair(es[5]) == (5 => 3)

    @test cols == ["cbwd", "No", "PRES", "TEMP"] # TODO: consider keeping them grouped

    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    d["nodes"][2]["id"] = "rescale" # artificially create ambiguous `id`
    @test_throws ArgumentError Pipelines.Configuration(d["nodes"], d["groups"])
end

@testset "groups schema" begin
    variable_config = Pipelines.VariableConfig(
        nodes = ["rescale", "log", "pca", "partition"],
        groups = ["weather"],
        cols = [
            "No", "year", "month", "day", "hour",
            "pm2.5", "DEWP", "TEMP", "PRES", "cbwd",
            "Iws", "Is", "Ir",
        ]
    )
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    for node in d["nodes"]
        card = node["card"]
        schema = Pipelines.card_schema(card["type"], variable_config) |> JSONSchema.Schema
        @test JSONSchema.validate(schema, card) === nothing
    end

    # exactly one between `nodes`, `groups`, and `cols` is allowed
    card = deepcopy(d["nodes"][1]["card"])
    card["inputs"] = Dict("groups" => ["weather"], "cols" => ["No"])
    schema = Pipelines.card_schema(card["type"], variable_config) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("oneOf", string(issue))
    card["inputs"] = Dict()
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("oneOf", string(issue))

    variable_config′ = variable_config
    schema = Pipelines.group_schema(variable_config′) |> JSONSchema.Schema
    @test JSONSchema.validate(schema, d["groups"]["weather"]) === nothing

    variable_config′ = @set variable_config.groups = ["wether"]
    card = d["nodes"][1]["card"]
    schema = Pipelines.card_schema(card["type"], variable_config′) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("weather", string(issue))
    @test occursin("wether", string(issue))

    variable_config′ = @set variable_config.cols = String[]
    schema = Pipelines.group_schema(variable_config′) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, d["groups"]["weather"])
    @test issue !== nothing
    @test occursin("TEMP", string(issue)) || occursin("PRES", string(issue))
end

@testset "pipeline validation" begin
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    cols = [
        "No", "year", "month", "day", "hour",
        "pm2.5", "DEWP", "TEMP", "PRES", "cbwd",
        "Iws", "Is", "Ir",
    ]

    nodes = d["nodes"]
    groups = Dict("weather" => ["colname"])
    @test_throws(
        r"Schema Validation Error for group weather(.)*oneOf"s,
        Pipelines.Pipeline(nodes, groups, validate_schema = true)
    )

    groups = Dict("weather" => Dict("cols" => ["mycol"]))
    p = Pipelines.Pipeline(nodes, groups, validate_schema = true)
    @test p.enriched_digraph.source_vars == ["cbwd", "No", "mycol"]

    # If `cols` are specified, the schema knows `mycol` is not available
    @test_throws(
        r"Schema Validation Error for group weather(.)*mycol"s,
        Pipelines.Pipeline(nodes, groups, cols, validate_schema = true)
    )

    groups = d["groups"]
    nodes[1]["card"]["extra_prop"] = 1
    @test_throws(
        r"Schema Validation Error for card in node 1(.)*extra_prop"s,
        Pipelines.Pipeline(nodes, groups, cols, validate_schema = true)
    )

    # without validating the schema, the spurious property is not an issue
    p = Pipelines.Pipeline(nodes, groups, cols, validate_schema = false)
    @test p.nodes[1].card isa RescaleCard
end

@testset "node_digraph" begin
    spec = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "spec.json"))
    repo = Repository()

    mktempdir() do dir
        Downloads.download(
            "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
            joinpath(dir, "pollution.csv")
        )
        DataIngestion.load_files(repo, dir, spec["data"])
    end
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    pipeline = Pipelines.Pipeline(d["nodes"], d["groups"])
    @test Pipelines.get_source_vars(pipeline) == [
        "cbwd",
        "No",
        "PRES",
        "TEMP",
    ]
    @test Pipelines.get_output_vars(pipeline) == [
        "PRES_rescaled",
        "TEMP_rescaled",
        "No_rescaled",
        "No_log",
        "component_1",
        "component_2",
        "partition",
    ]

    Pipelines.train_evaljoin!(repo, pipeline, "source", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM source")
    # order-insensitive: `evaljoin_many` appends independent nodes' columns
    # concurrently, so column order is not deterministic under multithreading.
    @test issetequal(
        names(df),
        [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "No_log", "partition",
            "PRES_rescaled", "TEMP_rescaled", "No_rescaled", "component_1", "component_2",
        ]
    )
end
