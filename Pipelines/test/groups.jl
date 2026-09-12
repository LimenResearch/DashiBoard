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

@testset "unproduced references (A10)" begin
    base = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    available = ["No", "PRES", "TEMP", "cbwd"]

    function issues(inputs)
        d = deepcopy(base)
        d["nodes"][3]["card"]["inputs"] = inputs
        p = Pipelines.Pipeline(d["nodes"], d["groups"], available)
        return Pipelines.unproduced_references(p, available)
    end

    # A chain that names something a node actually emits.
    @test isempty(issues([Dict("cols" => "PRES", "through" => ["rescale"])]))

    # A chain that names a column nothing emits: `log` consumes `No` and emits only `No_log`, so
    # `PRES_rescaled_log` exists nowhere. Validation accepts it; this is what catches it.
    found = issues([Dict("cols" => "PRES", "through" => ["rescale", "log"])])
    @test length(found) == 1
    node_idx, missing_cols = only(found)
    @test node_idx == 3                       # the `pca` node
    @test missing_cols == ["PRES_rescaled_log"]

    # The untouched fixture is clean, so this does not fire on well-formed documents.
    p = Pipelines.Pipeline(base["nodes"], base["groups"], available)
    @test isempty(Pipelines.unproduced_references(p, available))
end

# A7 — a schema failure comes back as data a form can act on, not prose it can only print.
#
# Every expectation below was measured against JSONSchema.jl rather than read off its source, and
# two of them contradict what `06-design.md` recorded before the fixtures were run:
#
#   * `SingleIssue.path` indexes arrays the Julia way. The third element reports `[inputs][3]`,
#     so a JSON Pointer must subtract one — otherwise the form highlights the wrong row.
#   * a `required` failure carries *every* required name in `val`, not the missing one, and
#     reports at the parent path. The missing name is `val` minus the keys actually present.
@testset "A7: a validation failure as data" begin
    cols = ["No", "TEMP", "PRES"]
    groups = Dict{String, Any}("weather" => [Dict("cols" => ["PRES", "TEMP"])])
    node(card) = [Dict{String, Any}("id" => "r", "card" => card)]

    function report(card; grps = groups)
        err = try
            Pipelines.Pipeline(node(card), grps, cols)
            nothing
        catch exception
            exception
        end
        @test err isa Pipelines.SchemaValidationError
        return Pipelines.issue_report(err)
    end

    rescale(; kw...) = merge(
        Dict{String, Any}(
            "type" => "rescale", "method" => Dict("type" => "zscore"),
            "inputs" => [Dict("cols" => "TEMP")],
        ),
        Dict{String, Any}(string(k) => v for (k, v) in pairs(kw)),
    )

    # An unknown variant names the variants that exist — the difference between a form that can
    # offer a correction and one that can only say no.
    bad_variant = report(rescale(method = Dict("type" => "nonesuch")))
    @test bad_variant.pointer == "/nodes/0/card/method/type"
    @test bad_variant.reason == "enum"
    @test bad_variant.found == "nonesuch"
    @test "zscore" in bad_variant.allowed

    # The pointer addresses the *document*, not the card: the UI holds the whole document, and a
    # card-local pointer would be ambiguous the moment there are two cards.
    deep = report(Dict{String, Any}(
        "type" => "cluster", "inputs" => [Dict("cols" => "TEMP")],
        "method" => Dict(
            "type" => "dbscan", "radius" => 0.5,
            "dissimilarity" => Dict("type" => "minkowski", "p" => -5),
        ),
    ))
    @test deep.pointer == "/nodes/0/card/method/dissimilarity/p"
    @test deep.reason == "minimum"

    # The index conversion, on the case that tells 0-based from 1-based. Julia says [inputs][3].
    third = report(rescale(inputs = [
        Dict("cols" => "No"), Dict("cols" => "TEMP"), Dict("cols" => "NOPE"),
    ]))
    @test third.pointer == "/nodes/0/card/inputs/2/cols"
    @test third.allowed == cols

    # `required` reports at the parent, so the pointer alone does not identify the control. The
    # missing name has to be recovered, and `related` addresses the control that is absent.
    missing_method = report(Dict{String, Any}(
        "type" => "rescale", "inputs" => [Dict("cols" => "TEMP")],
    ))
    @test missing_method.pointer == "/nodes/0/card"
    @test missing_method.reason == "required"
    @test missing_method.missing == ["method"]
    @test missing_method.related == ["/nodes/0/card/method"]

    # A group is addressed by name, not position: `groups` is an object in the document.
    bad_group = report(rescale(); grps = Dict{String, Any}("weather" => [Dict("cols" => "NOPE")]))
    @test bad_group.pointer == "/groups/weather/0/cols"
    @test bad_group.reason == "enum"

    # The prose survives alongside the data, for anything that only knows how to print.
    @test occursin("enum", bad_variant.message) || !isempty(bad_variant.message)
end

# A defaulted *variant* field must carry its default into the IR.
#
# `DBSCANMethod` declares `dissimilarity::D = EuclideanMethod()`, so a form rendering that card has
# everything it needs to fill the field in — but only if the IR says which option the default is.
# It did not: `@options`' `IR_from_type` compared the default *instance* against a Dict whose
# values are *types*, so `findfirst(==(_default), methods)` never matched and `default_option` came
# out `nothing`. Nothing downstream could tell "no default" from "a default we failed to name".
@testset "a defaulted variant names its default option" begin
    ir = Pipelines.card_ir("cluster")
    method = only(p for p in ir.properties if p.key == "method").value
    dbscan = method.objects["dbscan"]
    dissimilarity = only(p for p in dbscan.properties if p.key == "dissimilarity").value

    @test dissimilarity.default_option == "euclidean"
    # and the option it names is one the field actually offers
    @test dissimilarity.default_option in dissimilarity.options

    # kmeans defaults to squared euclidean, which is a different branch of the same vocabulary —
    # so this is the default of the *field*, not of the type.
    kmeans = method.objects["kmeans"]
    kdiss = only(p for p in kmeans.properties if p.key == "dissimilarity").value
    @test kdiss.default_option == "sqeuclidean"

    # A field with no declared default still says so, rather than inventing one.
    @test method.default_option === nothing
end
