"""
    data_directory() -> String

The directory every file route is confined to, absolute and normalised. `pwd()` when the server
was launched without one, which is `DataIngestion.acceptable_paths`'s own rule — so the listing
here and the loader there agree on where "here" is.
"""
function data_directory()
    dir = DataIngestion.DATA_DIR[]
    return normpath(abspath(isempty(dir) ? pwd() : dir))
end

"""
    resolve_in_data_dir(path) -> String

`path`, read relative to the data directory, as an absolute path — or an `ArgumentError` if it
leaves that directory.

The one path function of the file routes. A client names files by the relative paths
`list-files` gave it, but nothing stops a request from saying `../../etc/passwd`, and
`load-files` used to join such a path without looking. Compared through `relpath` rather than
`startswith`, which would let `/data-evil` pass for `/data`.
"""
function resolve_in_data_dir(path::AbstractString)
    outside() = throw(ArgumentError("`$(path)` is outside the data directory"))
    isabspath(path) && outside()
    base = data_directory()
    full = normpath(joinpath(base, path))
    rel = relpath(full, base)
    (rel == ".." || startswith(rel, ".." * Base.Filesystem.path_separator)) && outside()
    return full
end

# What makes a parsed file a document of the UI rather than a table: the keys `Download cards`
# and `Download filters` write. Told by content, not by name, so the kind survives a rename and
# a `.json` that is a real table (DataIngestion's `json_reader`) stays a table.
const DOCUMENT_SHAPES = (
    "cards" => ("nodes", "groups"),
    "filters" => ("numerical", "categorical"),
)

"""
    document_kind(parsed) -> Union{String, Nothing}

`"cards"`, `"filters"`, or `nothing` when `parsed` is neither.
"""
function document_kind(parsed)
    parsed isa AbstractDict || return nothing
    for (kind, required) in DOCUMENT_SHAPES
        all(key -> haskey(parsed, key), required) && return kind
    end
    return nothing
end

"""
    parse_document(full) -> parsed

Read a JSON or a TOML file, by extension. TOML because it is Pipelines' configuration format
and a cards document written by hand is as likely to be one; JSON because it is what the UI
writes.
"""
function parse_document(full::AbstractString)
    ext = lowercase(last(splitext(full)))
    ext == ".json" && return JSON.parsefile(full)
    ext == ".toml" && return TOML.parsefile(full)
    throw(ArgumentError("`$(basename(full))` is neither JSON nor TOML"))
end

"""
    file_kind(full) -> Union{String, Nothing}

`"table"`, `"cards"`, `"filters"`, or `nothing` for a file the UI has no use for.

A JSON or TOML file is parsed to find out: a document is small, a JSON table is rare, and a peek
at the whole file is what lets a renamed document keep its kind. One that does not parse is
`nothing` — a half-written file must not break the listing, and the listing is not where a parse
error is reported (`read_document` is).
"""
function file_kind(full::AbstractString)
    ext = lowercase(last(splitext(full)))
    if ext in (".json", ".toml")
        parsed = try
            parse_document(full)
        catch
            return nothing
        end
        kind = document_kind(parsed)
        isnothing(kind) || return kind
        return ext == ".json" ? "table" : nothing
    end
    return DataIngestion.is_supported(full) ? "table" : nothing
end

"""
    list_files(req)

Every file under the data directory the UI may pick, as `[{path, kind}]` — relative paths,
subfolders included, sorted. Supersedes `get-acceptable-paths`, which listed tables only: cards
and filters documents used to come in through the browser's own file dialog, which shows the
whole disk, while tables were confined to this directory. One listing, one visibility.

Hidden files and folders are skipped. A data directory that does not exist answers `[]` and
warns: `walkdir` throws on it, which reached the client as a 500 with an empty body and the log
as a 200 (`LoggingMiddleware` records the status set *before* a throw).
"""
function list_files(req::HTTP.Request)
    _ = json_read(req)
    base = data_directory()
    if !isdir(base)
        @warn "the data directory does not exist" base
        return json_response([])
    end
    files = @NamedTuple{path::String, kind::String}[]
    for (root, dirs, names) in walkdir(base)
        # `walkdir` is top-down, so pruning `dirs` in place keeps it out of hidden folders.
        filter!(dir -> !startswith(dir, "."), dirs)
        for name in names
            startswith(name, ".") && continue
            kind = file_kind(joinpath(root, name))
            isnothing(kind) && continue
            push!(files, (; path = normpath(relpath(root, base), name), kind))
        end
    end
    sort!(files, by = file -> file.path)
    return json_response(files)
end

"""
    read_document(req)

A cards or filters document from the data directory: `{valid: true, document}`, or the failure
envelope every other route uses, with the server's sentence. Wrapped rather than returned bare,
so a client tells a reply from a failure by `valid` alone, never by guessing at a document's keys.

The counterpart of the browser's file dialog, which read a local file the server never saw and
showed the whole disk. `kind` is what the client expects: a filters file picked where cards
were asked for is refused here, with a sentence, rather than loaded into the wrong store.
"""
function read_document(req::HTTP.Request)
    spec = json_read(req)
    answer = try
        path, kind = spec["path"], spec["kind"]
        full = resolve_in_data_dir(path)
        isfile(full) || throw(ArgumentError("`$(path)` does not exist"))
        document = parse_document(full)
        document_kind(document) == kind || throw(ArgumentError("`$(path)` is not a $(kind) document"))
        (; valid = true, document)
    catch exception
        failure_report("document", exception)
    end
    return json_response(answer)
end

"""
    write_document(req)

Save a cards or filters document into the data directory, as indented JSON: `{valid: true, path}`
or the failure envelope. What makes a document round-trip where it can be loaded again — the
browser's Download puts the file in a folder `list-files` never sees.

Refuses: a path outside the directory; a name that does not end in `.json` (TOML is read, not
written); a document whose shape is not `kind`'s; a folder that does not exist (no folders are
created on a client's word); an existing file, unless `overwrite` is `true`.
"""
function write_document(req::HTTP.Request)
    spec = json_read(req)
    answer = try
        path, kind, document = spec["path"], spec["kind"], spec["document"]
        full = resolve_in_data_dir(path)
        lowercase(last(splitext(full))) == ".json" ||
            throw(ArgumentError("documents are saved as JSON: `$(path)` does not end in .json"))
        document_kind(document) == kind || throw(ArgumentError("this is not a $(kind) document"))
        isdir(dirname(full)) || throw(ArgumentError("the folder of `$(path)` does not exist"))
        (isfile(full) && get(spec, "overwrite", false) !== true) &&
            throw(ArgumentError("`$(path)` already exists"))
        write(full, JSON.json(document; pretty = true))
        (; valid = true, path)
    catch exception
        failure_report("document", exception)
    end
    return json_response(answer)
end

function load_files(req::HTTP.Request)
    spec = json_read(req)
    # Checked here, not in `DataIngestion.parse_paths`, which joins `..` without looking and is
    # not ours to change: a client names files by the relative paths `list-files` gave it, and a
    # path that leaves the data directory is refused before anything is read.
    try
        foreach(resolve_in_data_dir, spec["files"])
    catch exception
        return json_response(failure_report("load", exception))
    end
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
    card_schema_issues(nodes, groups, cols) -> Vector

The cards' schema failures, asked for on their own — for the one case where the build cannot be
relied on to report them: a document that also has an empty group.

`empty_group_issues` has to answer before the pipeline is built (see there), and it used to end
the reply, so the cards were never looked at: a document with an empty group *and* a broken card
named the group only, and the card turned red one fix and one question later (seen in a browser,
2026-09-21, loading a document). The constructor validates the whole document before it builds
anything, so a schema failure still arrives as `SchemaValidationErrors` whatever the groups
hold; anything else it throws here is the empty group's own consequence (a card built with no
inputs), which `empty_group_issues` already says in better words, and is dropped.
"""
function card_schema_issues(nodes::AbstractVector, groups::AbstractDict, cols)
    try
        Pipelines.Pipeline(nodes, groups, cols)
    catch exception
        exception isa Pipelines.SchemaValidationErrors && return Pipelines.issue_report(exception)
    end
    return []
end

"""
    loop_issues(nodes, groups) -> Vector

One issue per loop in the document's dependency graph, naming its members.

A loop is a fault of the document, not of any one card, and the sentence Graphs.jl has for it —
"The input graph contains at least one loop." — names nothing, so a client could only repeat it
on whichever card happened to be asked (seen in a browser, 2026-09-18, on every card). The members
are recoverable without sorting: `Pipelines.dependency_graph` builds the graph and only the
later topological sort throws, so the strongly connected components with more than one vertex
(or a self-edge) are exactly the loops. Vertices are the nodes in document order, then the groups
in `pairs(groups)` order — the numbering `dependency_graph` itself uses.

The issue points at no item (`pointer = ""`): that is what tells a client it belongs to the
document. The members are under `related`, as pointers, and in the message, by name.
"""
function loop_issues(nodes::AbstractVector, groups::AbstractDict)
    graph, = Pipelines.dependency_graph(nodes, groups)
    n_nodes = length(nodes)
    group_names = collect(String, keys(groups))
    pointer(i) = i <= n_nodes ? "/nodes/$(i - 1)" :
        "/groups/" * Pipelines.escape_pointer(group_names[i - n_nodes])
    function label(i)
        i <= n_nodes || return group_names[i - n_nodes]
        id = Pipelines.get_id(nodes[i])
        return isempty(id) ? "card $(i)" : id
    end
    loops = [
        sort(component) for component in strongly_connected_components(graph)
            if length(component) > 1 || has_edge(graph, only(component), only(component))
    ]
    sort!(loops, by = first)
    return [
        (;
            pointer = "",
            reason = "loop",
            severity = "error",
            found = nothing,
            allowed = nothing,
            missing = String[],
            related = pointer.(members),
            message = "The input graph contains at least one loop: " * join(label.(members), ", "),
        )
            for members in loops
    ]
end

"""
    build_failure(nodes, groups, exception)

The failure envelope for a document that could not be built — `failure_report`, with a loop
named when that is what stopped it. Asked of the graph rather than read off the exception's
text: a loop is there or it is not, whatever Graphs.jl chooses to call it. Anything that goes
wrong while looking (two nodes with one id make `dependency_graph` itself throw) leaves the
plain report, which already carries that sentence.
"""
function build_failure(nodes::AbstractVector, groups::AbstractDict, exception::Exception)
    report = failure_report("pipeline", exception)
    isempty(report.issues) || return report
    loops = try
        loop_issues(nodes, groups)
    catch
        return report
    end
    isempty(loops) && return report
    return (; report..., errors = [issue.message for issue in loops], issues = loops)
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
    overwrite_warnings(pipeline, cols)

A warning per node whose outputs replace a column that already exists — in the source, or emitted
by an earlier node.

`rescale TEMP suffix = "rescaled"` against a source that already holds `TEMP_rescaled` is accepted
at every layer and silently replaces the column (A13, measured 2026-09-13 and on 1M rows
2026-09-16). Overwriting can be meant, so `severity = "warning"`: `valid` stays true and the run is
allowed; the form shows it on the card. Nodes are walked in document order, so the later of two
cards emitting the same name is the one warned, and a name is compared against everything that
exists *before* the node runs.
"""
function overwrite_warnings(pipeline, cols::AbstractVector)
    seen = Set{String}(cols)
    warnings = []
    for (i, node) in enumerate(pipeline.nodes)
        outputs = Pipelines.get_node_outputs(node)
        clashing = [name for name in outputs if name in seen]
        if !isempty(clashing)
            push!(warnings, (;
                pointer = "/nodes/$(i - 1)/card",
                reason = "overwrites",
                severity = "warning",
                found = nothing,
                allowed = nothing,
                missing = String[],
                related = String[],
                message = join(("`$(name)` already exists and will be replaced" for name in clashing), "; "),
            ))
        end
        union!(seen, outputs)
    end
    return warnings
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
    # The cards' own schema failures go out in the same answer (`card_schema_issues`), groups
    # first as in the document.
    empty = empty_group_issues(groups)
    if !isempty(empty)
        issues = vcat(empty, card_schema_issues(spec["nodes"], groups, cols))
        return json_response((;
            valid = false, kind = "pipeline", cols,
            errors = [issue.message for issue in issues], issues,
        ))
    end

    pipeline = try
        Pipelines.Pipeline(spec["nodes"], groups, cols)
    catch exception
        exception isa Exception || rethrow()
        # Always `pipeline`: this route resolves and never runs, so a fault it can see is by
        # construction a fault of the document. Deliberately not logged — the probe fires on every
        # edit, and most edits are documents the author has not finished writing yet.
        return json_response((; build_failure(spec["nodes"], groups, exception)..., cols))
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
        # Errors first, then warnings: a client reading the list top-down sees what blocks the
        # run before what merely deserves a look.
        issues = vcat(unproduced_issues, overwrite_warnings(pipeline, cols)),
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
        # Before building: see `empty_group_issues` for why construction cannot report this itself.
        # No `cols` in this envelope, unlike the probe's: a failure on this route has never carried
        # one — `failure_report` is `(; valid, kind, errors, issues)` — and the run's client asks
        # the probe for the column list.
        empty = empty_group_issues(groups)
        if !isempty(empty)
            # With the cards' own schema failures, as the probe answers (`card_schema_issues`).
            issues = vcat(empty, card_schema_issues(spec["nodes"], groups, cols))
            return json_response((;
                valid = false, kind = "pipeline",
                errors = [issue.message for issue in issues], issues,
            ))
        end
        Pipelines.Pipeline(spec["nodes"], groups, cols)
    catch exception
        exception isa Exception || rethrow()
        @error "evaluate-pipeline: could not build the pipeline" exception =
            (exception, catch_backtrace())
        return json_response(build_failure(spec["nodes"], get(spec, "groups", Dict{String, Any}()), exception))
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

"""
    finite_projection(repository, table)

`Select` every column of `table`, with each floating-point column replaced by
`CASE WHEN isfinite(col) THEN col END`.

DuckDB's JSON writer emits bare `NaN` and `Infinity`, which are not JSON: a page of a z-scored
constant column was unreadable to the browser (A12, measured 2026-09-16). The cast happens in
SQL so the page is written once and never post-processed as text. Column types come from
`information_schema`, which is a catalogue lookup — not a pass over the table.

It changes how those rows sort: a non-finite value reaches the sort as `NULL` — last under `ASC`
in DuckDB — rather than as the `NaN` it used to be.
"""
function finite_projection(repository, table::AbstractString)
    types = DBInterface.execute(
        DataFrame, repository,
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '$(table)'",
    )
    floaty = Set(("DOUBLE", "FLOAT", "REAL"))
    return Select((
        name => (type in floaty ? Fun.case(Fun.isfinite(Get(name)), Get(name)) : Get(name))
            for (name, type) in zip(types.column_name, types.data_type)
    )...)
end

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
        q = From(table) |> finite_projection(REPOSITORY[], table) |>
            Order(by = sorter_nodes) |> Limit(; limit, offset)
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
