@testset "groups" begin
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    g, nds, grps, cols = Pipelines.dependency_graph(d["nodes"], d["groups"])
    es = sort(collect(edges(g)))

    node_idxs = Dict(
        "rescale" => 1,
        "log" => 2,
        "pca" => 3,
        "partition" => 4,
    )
    group_idxs = Dict("weather" => 5)

    @test nds[1]["card"]["group_by"][1].inputs.cols == ["cbwd"]
    @test nds[1]["card"]["inputs"][1].inputs.idxs == [group_idxs["weather"]]
    @test nds[1]["card"]["inputs"][2].inputs.cols == ["No"]
    @test nds[1]["card"]["partition"].inputs.idxs == [node_idxs["partition"]]

    @test nds[2]["card"]["inputs"][1].inputs.cols == ["No"]

    @test nds[3]["card"]["inputs"][1].inputs.idxs == [node_idxs["log"]]
    @test nds[3]["card"]["inputs"][2].inputs.idxs == [group_idxs["weather"]]
    @test nds[3]["card"]["inputs"][2].through == [node_idxs["rescale"]]

    @test nds[4]["card"]["order_by"][1].inputs.cols == ["No"]

    @test only(grps[1]).inputs.cols == ["PRES", "TEMP"]
    @test only(grps[1]).through == String[]

    @test length(es) == 5
    @test Pair(es[1]) == (1 => 3)
    @test Pair(es[2]) == (2 => 3)
    @test Pair(es[3]) == (4 => 1)
    @test Pair(es[4]) == (5 => 1)
    @test Pair(es[5]) == (5 => 3)

    @test cols == ["cbwd", "No", "PRES", "TEMP"] # TODO: consider keeping them grouped

    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    d["nodes"][2]["id"] = "rescale" # artificially create ambiguous `id`
    @test_throws ArgumentError Pipelines.dependency_graph(d["nodes"], d["groups"])
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
    card["inputs"] = [Dict("groups" => ["weather"], "cols" => ["No"])]
    schema = Pipelines.card_schema(card["type"], variable_config) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("oneOf", string(issue))
    card["inputs"] = [Dict()]
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

    groups = Dict("weather" => [Dict("cols" => "mycol")])
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

@testset "graphviz for GroupDiGraph" begin
    # A4: `graphviz` dispatched on the concrete `EnrichedDiGraph`, so a group-API pipeline raised
    # a MethodError. Widening the signature would have been worse than the error: a
    # `GroupDiGraph`'s vertices are the nodes followed by the *groups*, with no variable vertices
    # at all, so the variable labels would have been attached to group vertices silently.
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    p = Pipelines.Pipeline(d["nodes"], d["groups"])
    dot = sprint(Pipelines.graphviz, p)

    @test startswith(dot, "digraph G{")
    # one labelled vertex per node, plus one per group — and nothing else
    @test count("[label = ", dot) == length(d["nodes"]) + length(d["groups"])
    # the group appears by name rather than by its resolved columns
    @test occursin("\"weather\"", dot)
    @test !occursin("PRES_rescaled", dot)
    # every edge references a vertex that exists
    for m in eachmatch(r"\"(\d+)\"", dot)
        @test parse(Int, m.captures[1]) <= length(d["nodes"]) + length(d["groups"])
    end
end

@testset "group ir_definitions and schema_definitions agree" begin
    vc = Pipelines.VariableConfig(nodes = ["log"], groups = ["weather"], cols = ["No", "TEMP"])
    irs = Pipelines.ir_definitions(vc)
    schemas = Pipelines.schema_definitions(vc)

    @test sort(collect(keys(irs))) == sort(collect(keys(schemas)))
    for (k, v) in pairs(irs)
        @test Pipelines.json_schema(v) == schemas[k]
    end

    # the group dialect's `variable` is a selector object, not the flat dialect's string enum
    @test irs["variable"].type == "object"
    @test irs["col"].enum == ["No", "TEMP"]
    @test irs["node"].enum == ["log"]
    # and its one-or-many fields are now identifiable by a renderer
    nodes_entry = only(p for p in irs["variable"].properties if p.key == "nodes")
    @test nodes_entry.value.type == "one_or_many"
end

# The specification of what the variable picker (C2) must be able to express. Each case below was
# established by running it, not by reading the schema, and the ones that look redundant are the
# ones a simplification would quietly break — see `06-design.md`, "C2 in detail".
@testset "selector cases the picker must express" begin
    base = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    cols = ["No", "PRES", "TEMP", "cbwd"]

    # Resolve node `pca`'s inputs for a given selector list.
    function resolve(inputs)
        d = deepcopy(base)
        d["nodes"][3]["card"]["inputs"] = inputs
        return Pipelines.Pipeline(d["nodes"], d["groups"], cols).nodes[3].card.inputs
    end
    rejects(inputs) = (@test_throws Pipelines.SchemaValidationError resolve(inputs))

    # A ≡ B: one item with two values and two items with one value each are indistinguishable.
    # So the item boundary carries no meaning *until* a `through` differs.
    @test resolve([Dict("cols" => ["PRES", "TEMP"])]) == ["PRES", "TEMP"]
    @test resolve([Dict("cols" => "PRES"), Dict("cols" => "TEMP")]) == ["PRES", "TEMP"]

    # C: same kind, different `through`. This is why `through` cannot be a field-level property.
    @test resolve([
        Dict("cols" => "PRES", "through" => ["rescale"]), Dict("cols" => "TEMP"),
    ]) == ["PRES_rescaled", "TEMP"]

    # D: one item, several values, a shared `through`.
    @test resolve([Dict("cols" => ["PRES", "TEMP"], "through" => ["rescale"])]) ==
        ["PRES_rescaled", "TEMP_rescaled"]

    # E: the same column twice, once passed through and once raw — both survive. Any UI modelling
    # a field as "a set of columns with attributes" cannot express this: there is nowhere to put
    # the second PRES.
    @test resolve([
        Dict("cols" => "PRES", "through" => ["rescale"]), Dict("cols" => "PRES"),
    ]) == ["PRES_rescaled", "PRES"]

    # F/G: the `oneOf` gate. Two kinds in one item, or none, are refused — so A7's
    # "unrepresentably wrong" is already enforced server-side; the UI doing it is defence in depth.
    rejects([Dict("cols" => "PRES", "groups" => "weather")])
    rejects([Dict{String, Any}()])

    # Order is preserved and meaningful, across kinds and within one. Until section 12 designs the
    # positional `weights` rule out, a UI that concatenates by kind silently changes the result.
    @test resolve([Dict("nodes" => "log"), Dict("groups" => "weather", "through" => ["rescale"])]) ==
        ["No_log", "PRES_rescaled", "TEMP_rescaled"]
    @test resolve([Dict("groups" => "weather", "through" => ["rescale"]), Dict("nodes" => "log")]) ==
        ["PRES_rescaled", "TEMP_rescaled", "No_log"]
    @test resolve([Dict("cols" => "TEMP"), Dict("cols" => "PRES")]) == ["TEMP", "PRES"]

    # `through` is an ordered *list* of nodes whose suffixes concatenate, not a single node.
    # So a Through panel keys on an ordered combination: [log, rescale] ≠ [rescale, log].
    @test resolve([Dict("cols" => "PRES", "through" => ["rescale"])]) == ["PRES_rescaled"]
    @test resolve([Dict("cols" => "PRES", "through" => ["log", "rescale"])]) == ["PRES_log_rescaled"]

    # THE GAP, pinned deliberately. `through` builds a column *name* by concatenating suffixes;
    # validation checks only that the base column exists in the source. Nothing produces
    # `PRES_rescaled_log` — `log` consumes `No` and emits `No_log` — yet this is accepted here and
    # fails later inside a task, naming neither the column nor the node. If someone adds that
    # check, this test should start failing and be updated rather than deleted.
    @test resolve([Dict("cols" => "PRES", "through" => ["rescale", "log"])]) == ["PRES_rescaled_log"]

    # What *is* caught: a `through` naming the consuming node makes the dependency graph cyclic.
    @test_throws ErrorException resolve([Dict("cols" => "PRES", "through" => ["rescale", "pca"])])

    # An empty `through` resolves identically to an absent one, so "Direct" is just a Through
    # section with an empty chain — one component, not two.
    @test resolve([Dict("cols" => "PRES", "through" => String[])]) ==
        resolve([Dict("cols" => "PRES")])
end
