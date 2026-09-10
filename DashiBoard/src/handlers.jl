function get_acceptable_paths(req::HTTP.Request)
    _ = json_read(req)
    files = collect(String, acceptable_paths())
    return json_response(files)
end

function load_files(req::HTTP.Request)
    spec = json_read(req)
    DataIngestion.load_files(REPOSITORY[], spec)
    summaries = DataIngestion.summarize(REPOSITORY[], "source")
    return json_response(summaries)
end

function get_card_widgets(req::HTTP.Request)
    spec = json_read(req)
    configs = Pipelines.card_widgets(spec)
    return json_response(configs)
end

"""
    get_card_ir(req)

Serve the renderer's artefact: the IR for every registered card, plus the shared `\$defs` once
in the envelope rather than duplicated per card. These are the two artefacts of one traversal, §13.

Serves the **group** dialect, matching what `evaluate-pipeline` now runs: a `variable` is a
selector object over nodes, groups and cols rather than a bare column-name enum. The request
carries all three vocabularies, because which nodes and groups are referenceable depends on the
document being edited, not only on the source.
"""
function get_card_ir(req::HTTP.Request)
    spec = json_read(req)
    # `nothing` means *unconstrained* in a `VariableConfig` (A9), so an absent key leaves that
    # definition without an enum rather than with an empty one — which would admit nothing.
    maybe_strings(key) = haskey(spec, key) ? collect(String, spec[key]) : nothing
    variable_config = Pipelines.VariableConfig(
        nodes = maybe_strings("nodes"),
        groups = maybe_strings("groups"),
        cols = maybe_strings("cols"),
    )
    defs = Pipelines.ir_definitions(variable_config)
    cards = Dict{String, Any}(k => Pipelines.card_ir(k) for k in keys(Pipelines.CARD_SPECS))
    return json_response((; defs, cards); omit_null = true)
end

"""
    probe_pipeline(req)

Resolve a document without running it: which columns each node consumes and emits, and any it
references that nothing produces (A10).

Construction is the cheap half of `evaluate-pipeline` — it resolves the group vocabulary and
validates against the schema — so a probe costs a graph walk and no data access beyond reading the
source table's column names. Nothing is materialised, so this is safe to call on every edit.

It reports rather than throws, for *every* way a document can be malformed rather than only
schema failures: a probe that answers 500 tells a form nothing it can render. Two nodes with no
`id`, for instance, both resolve to `""` and the dependency graph rejects them as duplicates —
an `ArgumentError`, which used to escape and leave the form silent.

Construction is pure document processing, so anything it raises is a fact about the document and
belongs in the response.
"""
function probe_pipeline(req::HTTP.Request)
    spec = json_read(req)
    cols = colnames(REPOSITORY[], "source")
    groups = get(spec, "groups", Dict{String, Any}())

    pipeline = try
        Pipelines.Pipeline(spec["nodes"], groups, cols)
    catch exception
        exception isa Exception || rethrow()
        return json_response((; valid = false, cols, errors = [sprint(showerror, exception)]))
    end

    absent = Dict(Pipelines.unproduced_references(pipeline, cols))
    # `Pipelines.get_id` is the naming rule everything else uses; inventing an index here made
    # this the third answer to "what is this node called" in three files.
    ids = Pipelines.get_id.(spec["nodes"])
    nodes = map(enumerate(pipeline.nodes)) do (i, node)
        return (;
            id = ids[i],
            inputs = Pipelines.get_node_inputs(node),
            outputs = Pipelines.get_node_outputs(node),
            unproduced = get(absent, i, String[]),
        )
    end

    return json_response((;
        valid = isempty(absent),
        cols,
        nodes,
        source_vars = Pipelines.get_source_vars(pipeline),
        output_vars = Pipelines.get_output_vars(pipeline),
        errors = String[],
    ))
end

"""
    evaluate_pipeline(req)

Run an authored document. Takes the **group dialect** — `{filters, nodes, groups}`, with
selector-form variable fields — which is what the UI authors and what ExperimentTracking stores.

This route used to take the flat `{filters, cards}` shape, and 06-design.md's "Do not do" once said
not to migrate it, on the premise that the new UI would serve against ExperimentTracking and this
server would be deleted. Under the standalone-first scope the new UI serves against *this* server
until B1 and B6 land, so leaving it flat-only meant the UI could not preview the group vocabulary
that §6's variable picker exists to author.
"""
function evaluate_pipeline(req::HTTP.Request)
    spec = json_read(req)
    filters = Filter.(spec["filters"])

    orig = From("source") |> Partition() |> Define(ID_VAR[] => Agg.row_number())
    DataIngestion.select(REPOSITORY[], filters, orig => "selection")

    # The columns available *to* the pipeline, so the group API can validate references against
    # them rather than accepting a name that does not exist and failing later in SQL.
    available = DataIngestion.summarize(REPOSITORY[], "selection")
    cols = String[summary.name for summary in available]

    groups = get(spec, "groups", Dict{String, Any}())
    pipeline = Pipelines.Pipeline(spec["nodes"], groups, cols)
    p = Pipelines.train_evaljoin!(REPOSITORY[], pipeline, "selection", ID_VAR[])

    nodes = pipeline.nodes
    report = Pipelines.report(REPOSITORY[], nodes)
    vs = Pipelines.visualize(REPOSITORY[], nodes)
    visualization = stringify_visualization.(vs)
    graph = sprint(Pipelines.graphviz, p)
    # Recomputed: the pipeline has added its output columns since `available` was taken.
    summaries = DataIngestion.summarize(REPOSITORY[], "selection")
    return json_response((; summaries, visualization, graph, report))
end

struct Sorter
    colname::String
    sort::SQLNode
end

const ASC_DICT = Dict("asc" => Asc(), "desc" => Desc())

Sorter(d::AbstractDict) = Sorter(d["colId"], ASC_DICT[d["sort"]])

function fetch_data(stream::HTTP.Stream)
    spec = json_read(stream)
    table = spec["processed"] ? "selection" : "source"
    ns = Set{String}(colnames(REPOSITORY[], table))
    limit::Int, offset::Int = spec["limit"], spec["offset"]
    sort_model::Vector = get(spec, "sortModel", [])
    sorters = Sorter.(sort_model)
    sorter_nodes = [Get(s.colname) |> s.sort for s in sorters if s.colname in ns]

    mktempdir() do dir
        path = joinpath(dir, "data.json")
        q = From(table) |> Order(by = sorter_nodes) |> Limit(; limit, offset)
        export_table(
            REPOSITORY[], q, path;
            format = "json", array = true
        )

        nrows = DBInterface.execute(
            to_nrow,
            REPOSITORY[],
            From(table) |> Group() |> Select("Count" => Agg.count())
        )

        stream_data(
            stream, path, "application/json";
            pre = "{\"values\":", post = string(",\"length\":", nrows, "}")
        )
    end
    return
end

function get_processed_data(stream::HTTP.Stream)
    mktempdir() do dir
        path = joinpath(dir, "processed-data.csv")
        export_table(REPOSITORY[], From("selection"), path)
        stream_data(stream, path, "text/csv")
    end
    return
end
