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
    # Which halves to send. `cards` is the IR of every registered type and takes no vocabulary,
    # so it is the same answer for the life of the server; `defs` is the three enums and changes
    # with every column, group or node name. Measured: 18,449 of 19,152 bytes were `cards`, and
    # they were being refetched to update 242 bytes of enum.
    include = Set{String}(get(spec, "include", ["defs", "cards"]))
    parts = Pair{Symbol, Any}[]
    if "defs" in include
        variable_config = Pipelines.VariableConfig(
            nodes = maybe_strings("nodes"),
            groups = maybe_strings("groups"),
            cols = maybe_strings("cols"),
        )
        push!(parts, :defs => Pipelines.ir_definitions(variable_config))
    end
    if "cards" in include
        push!(parts, :cards => Dict{String, Any}(k => Pipelines.card_ir(k) for k in keys(Pipelines.CARD_SPECS)))
    end
    return json_response((; parts...); omit_null = true)
end

"""
    root_causes(exception) -> Vector{Exception}

Peel the scheduler off an exception, leaving what actually went wrong.

`Pipelines` evaluates nodes as tasks, so a failure inside a card reaches a handler wrapped in
`TaskFailedException` — twice over in practice, since the node loop spawns inside a spawn. Running
`showerror` on the wrapper prints the scheduler's stacktrace and not one word about the cause: a
missing column came back as "TaskFailedException" and forty lines of `threads_overloads.jl`, with
the sentence that names the fault buried two levels inside it.

A `CompositeException` expands rather than collapses, because several cards failing at once is
several things to say. `errors` is already a list, so they have somewhere to go.
"""
function root_causes(exception)::Vector{Exception}
    if exception isa TaskFailedException && exception.task.result isa Exception
        return root_causes(exception.task.result)
    elseif exception isa CompositeException
        return isempty(exception.exceptions) ? Exception[exception] :
            reduce(vcat, root_causes.(exception.exceptions))
    elseif exception isa Exception
        return Exception[exception]
    else
        # A task can fail with a value that is not an `Exception`; say so rather than throw here.
        return Exception[ErrorException(sprint(show, exception))]
    end
end

"""
    failure_report(kind, exception)

The body both pipeline routes answer with when they cannot do what was asked.

`kind` says *where* it broke, not whose fault it is: `"pipeline"` for a document that could not be
turned into a pipeline — a schema failure, a duplicate id, a cycle — and `"execution"` for one that
built and then died while running. That split is on which call threw, which is observable;
"is this the author's mistake or ours" is not, and a field that claims to know would be guessing.

A client reads the two the same way and means different things by them: a `pipeline` failure sends
the author back to the cards, an `execution` failure back to the data.
"""
function failure_report(kind::AbstractString, exception::Exception)
    # A7: a schema failure carries a JSON Pointer into the document and what would have been
    # accepted, so the form can address the control and offer a correction. Anything else — a
    # cyclic graph, a duplicate id, a binder error from DuckDB — has only its message.
    # A11: validation collects, so one failure and twenty arrive in the same shape.
    issues = exception isa Pipelines.SchemaValidationErrors ?
        Pipelines.issue_report(exception) : []
    return (;
        valid = false, kind,
        errors = [sprint(showerror, cause) for cause in root_causes(exception)],
        issues,
    )
end

"""
    validate_card(req)

Check one card against its own schema, without resolving a document.

The targeted counterpart to `probe-pipeline`. A form editing a single card needs to know whether
that card is answerable — has a method been chosen, are the inputs named — and none of that
depends on the other cards. Asking the whole document costs a graph walk and answers about the
first failing card rather than this one.

Takes the same vocabularies `get-card-ir` does, because the schema a card is checked against is
built from them: a column that does not exist is a schema failure only if the server knows which
columns do. `base` is where the card sits in the document, so the pointers come back
document-relative and the client reads them exactly as it reads the probe's.

What it cannot answer stays with the probe: unproduced references, duplicate ids, cycles — every
question that needs the other cards.
"""
function validate_card(req::HTTP.Request)
    spec = json_read(req)
    maybe_strings(key) = haskey(spec, key) ? collect(String, spec[key]) : nothing
    variable_config = Pipelines.VariableConfig(
        nodes = maybe_strings("nodes"),
        groups = maybe_strings("groups"),
        cols = maybe_strings("cols"),
    )
    return try
        issues = Pipelines.card_issues(
            spec["card"], variable_config; base = get(spec, "base", "")
        )
        json_response((; valid = isempty(issues), issues); omit_null = true)
    catch exception
        exception isa Exception || rethrow()
        # An unknown card type has no schema to build, and a malformed request has no card. Both
        # are faults of what was sent, so they answer in the same envelope as everything else.
        json_response(failure_report("pipeline", exception))
    end
end

"""
    empty_group_issues(groups)

One `pipeline`-kind issue per group that names no columns.

A group with an empty selector list is a legal document — `weather = []` constructs — and it
resolves to zero columns, so a card reading it is built with no inputs and dies inside the card
constructor with `UndefKeywordError: keyword argument args not assigned` (measured 2026-09-16,
smoke check 5). That message names the implementation, not the mistake. Checked here, before the
pipeline is built, because the group API keeps no provenance from a resolved column list back to
the group that produced it: by the time construction fails, which group was empty is no longer
knowable. Reported by the probe and by the run alike, in the same shape as a schema failure, so a
form addresses the group rather than printing a sentence above the page.
"""
function empty_group_issues(groups::AbstractDict)
    return [
        (;
            pointer = "/groups/" * Pipelines.escape_pointer(String(name)),
            reason = "empty",
            severity = "error",
            found = nothing,
            allowed = nothing,
            missing = String[],
            related = String[],
            message = "group `$(name)` has no columns",
        )
            for (name, items) in pairs(groups) if items isa AbstractVector && isempty(items)
    ]
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

A schema failure additionally comes back as `issues` — a JSON Pointer into the document, the
failing keyword, and what would have been accepted (A7) — which is the vehicle a form needs to
address the offending control rather than print a sentence above it.
"""
function probe_pipeline(req::HTTP.Request)
    spec = json_read(req)
    cols = colnames(REPOSITORY[], "source")
    groups = get(spec, "groups", Dict{String, Any}())

    # Before building: see `empty_group_issues` for why construction cannot report this itself.
    empty = empty_group_issues(groups)
    isempty(empty) || return json_response((;
        valid = false, kind = "pipeline", cols,
        errors = [issue.message for issue in empty], issues = empty,
    ))

    pipeline = try
        Pipelines.Pipeline(spec["nodes"], groups, cols)
    catch exception
        exception isa Exception || rethrow()
        # Always `pipeline`: this route resolves and never runs, so a fault it can see is by
        # construction a fault of the document. Deliberately not logged — the probe fires on every
        # edit, and most edits are documents the author has not finished writing yet.
        return json_response((; failure_report("pipeline", exception)..., cols))
    end

    absent = Dict(Pipelines.unproduced_references(pipeline, cols))
    # `Pipelines.get_id` is the naming rule everything else uses; inventing an index here made
    # this the third answer to "what is this node called" in three files.
    ids = Pipelines.get_id.(spec["nodes"])

    # A7's second error source. An unproduced reference is addressed at *node* granularity, not
    # at the selector item that named it: resolution returns the node's resolved column list and
    # keeps no provenance back to the item, so `{cols = "PRES", through = [...]}` cannot be
    # singled out from its siblings. Reported in the same shape as a schema failure so a form
    # iterates one list, with `reason` telling them apart.
    unproduced_issues = [
        (;
            pointer = "/nodes/$(i - 1)/card",
            reason = "unproduced",
            # an error: nothing produces the column, so the document cannot run
            severity = "error",
            found = nothing,
            allowed = nothing,
            missing = names,
            related = String[],
            message = "nothing produces " * join(names, ", "),
        )
            for (i, names) in sort!(collect(absent), by = first)
    ]
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
        # The probe's second way of being invalid, and the same kind as the first: a reference
        # nothing produces is a fault of the document, found by resolving rather than by running.
        kind = isempty(absent) ? nothing : "pipeline",
        cols,
        nodes,
        source_vars = Pipelines.get_source_vars(pipeline),
        output_vars = Pipelines.get_output_vars(pipeline),
        errors = String[],
        # Always present, so a client can read one shape rather than branch on which half of the
        # route answered.
        issues = unproduced_issues,
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

    # Running is the one step nothing static can vet. The probe answers everything that can be
    # known from the document alone, so what reaches here is a fault of the *data* — PCA asked for
    # more components than there are columns, a model that will not converge — and it surfaces only
    # by being run. Uncaught, the exception escaped to HTTP.jl, which answered with a bare 500
    # carrying zero bytes and no CORS header: the client could not show the error because it was
    # never sent one, and could not tell a failed run from a run that never happened.
    #
    # Answered in the probe's shape — 200 with `valid` — deliberately. A failed run is a fact about
    # the document and its data, which is the same reasoning `probe_pipeline` states, and one shape
    # means a client reads both replies the same way. The cost is that a genuine server fault also
    # arrives as `valid = false`; `@error` keeps the stacktrace where an operator will find it,
    # which the old bare 500 at least did by accident.
    # Everything up to a built pipeline, in one `pipeline`-kind guard: filtering, materialising
    # the selection, and construction itself. A client that probes first will rarely see this
    # branch — but the route is public and cannot assume it was asked politely. `filters` is read
    # with a default for the same reason: it was indexed directly, so a body without the key
    # answered with the same bare 500 this whole change exists to remove.
    pipeline = try
        filters = Filter.(get(spec, "filters", []))
        orig = From("source") |> Partition() |> Define(ID_VAR[] => Agg.row_number())
        DataIngestion.select(REPOSITORY[], filters, orig => "selection")

        # The columns available *to* the pipeline, so the group API can validate references
        # against them rather than accepting a name that does not exist and failing later in SQL.
        available = DataIngestion.summarize(REPOSITORY[], "selection")
        cols = String[summary.name for summary in available]

        groups = get(spec, "groups", Dict{String, Any}())
        empty = empty_group_issues(groups)
        isempty(empty) || return json_response((;
            valid = false, kind = "pipeline",
            errors = [issue.message for issue in empty], issues = empty,
        ))
        Pipelines.Pipeline(spec["nodes"], groups, cols)
    catch exception
        exception isa Exception || rethrow()
        @error "evaluate-pipeline: could not build the pipeline" exception =
            (exception, catch_backtrace())
        return json_response(failure_report("pipeline", exception))
    end

    return try
        p = Pipelines.train_evaljoin!(REPOSITORY[], pipeline, "selection", ID_VAR[])

        nodes = pipeline.nodes
        report = Pipelines.report(REPOSITORY[], nodes)
        vs = Pipelines.visualize(REPOSITORY[], nodes)
        visualization = stringify_visualization.(vs)
        graph = sprint(Pipelines.graphviz, p)
        # Recomputed: the pipeline has added its output columns since `available` was taken.
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        json_response((; valid = true, summaries, visualization, graph, report))
    catch exception
        exception isa Exception || rethrow()
        # Logged, unlike the probe's: this one was asked for deliberately, and an operator wants
        # the backtrace whether the cause was the data or a bug of ours.
        @error "evaluate-pipeline: the run failed" exception = (exception, catch_backtrace())
        json_response(failure_report("execution", exception))
    end
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
