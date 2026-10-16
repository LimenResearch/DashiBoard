# An absent directory is `pwd()`, which is `DataIngestion.acceptable_paths`'s own rule — so the
# listing here and the loader there agree on where "here" is.
absolute_or_here(dir::AbstractString) = tidy_path(abspath(isempty(dir) ? pwd() : dir))

"""
    workspace_directory() -> String

The directory every file route is confined to, absolute and normalised.
"""
workspace_directory() = absolute_or_here(WORKSPACE[])

"""
    pointer(kind::Symbol) -> String

Where the files of one kind are: `:data`, `:pipeline`, `:filter`, `:model` or `:training`. The
tables' and the configurations' directories are DataIngestion's and Pipelines' scoped values,
so a card is resolved against the same folders the Load tab lists.
"""
function pointer(kind::Symbol)
    # Pipelines' two have no default and read as unassigned until a server sets them.
    unset(v) = isassigned(v) ? v[] : ""
    dir = kind === :data ? DataIngestion.DATA_DIR[] :
        kind === :pipeline ? PIPELINE_DIR[] :
        kind === :filter ? FILTER_DIR[] :
        kind === :model ? unset(Pipelines.MODEL_DIR) :
        kind === :training ? unset(Pipelines.TRAINING_DIR) :
        throw(ArgumentError("no such kind of file: `$(kind)`"))
    return absolute_or_here(dir)
end

data_directory() = pointer(:data)

"""
    resolve_in(base, path; what = "the workspace") -> String

`path`, read relative to `base`, as an absolute path — or an `ArgumentError` naming `what` if it
leaves that directory.

The one path function of the file routes. A client names files by the relative paths
`list-files` gave it, but nothing stops a request from saying `../../etc/passwd`, so every route
that takes a path goes through here. Compared through `relpath` rather than `startswith`, which
would let `/data-evil` pass for `/data`.
"""
function resolve_in(base::AbstractString, path::AbstractString; what::AbstractString = "the workspace")
    outside() = throw(ArgumentError("`$(path)` is outside $(what)"))
    isabspath(path) && outside()
    full = normpath(joinpath(base, path))
    rel = relpath(full, base)
    # Across drives there is no relative path, and `relpath` answers an absolute one.
    (isabspath(rel) || rel == ".." || startswith(rel, ".." * Base.Filesystem.path_separator)) && outside()
    return full
end
resolve_in_data_dir(path::AbstractString) = resolve_in(data_directory(), path; what = "the data directory")

const configuration_kind = StreamlinerCore.configuration_kind

"""
    writable(path) -> path

`path` if a client may write there, an `ArgumentError` otherwise. Two things are the launcher's
alone: the workspace file, which names packages the next launch installs and loads, and hidden
folders, where its environment lives. A route that could write either would let whoever reaches
the server choose the code it runs next.
"""
function writable(path::AbstractString)
    segments = splitpath(path)
    # `.` and `..` are steps, not names: whether they lead outside is the resolver's to say.
    hidden(segment) = startswith(segment, ".") && segment != "." && segment != ".."
    any(hidden, segments) && throw(ArgumentError("`$(path)` is hidden, and hidden files and folders are not written to"))
    lowercase(last(segments)) == WORKSPACE_FILE && throw(ArgumentError("`$(path)`: the workspace file is not written through the server"))
    return path
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

# What a file under a kind's directory is expected to be.
const EXPECTED_KIND = Dict(:data => "table", :pipeline => "cards", :filter => "filters")

"""
    files_under(base; except) -> Vector{String}

Every file under `base`, as paths relative to it, sorted. Hidden entries, folders named like
the layout's own and the directories in `except` — the other kinds' own, when they sit inside
this one — are skipped.
"""
function files_under(base::AbstractString; except = String[])
    found = String[]
    for (root, dirs, names) in walkdir(base)
        # `walkdir` is top-down, so pruning `dirs` in place keeps it out of them.
        # The layout's folder names are not subfolder names: what sits in one is either
        # another kind's or set aside, and the kind routes would not read it.
        filter!(dirs) do dir
            !startswith(dir, ".") && !(dir in RESERVED) && !(normpath(joinpath(root, dir)) in except)
        end
        for name in names
            startswith(name, ".") && continue
            push!(found, normpath(relpath(joinpath(root, name), base)))
        end
    end
    return sort!(found)
end

# How a kind's directory reads from the workspace: `data`, a longer path when it is nested, the
# whole path when it is elsewhere, and nothing when it is the workspace itself.
function folder_label(kind::Symbol)
    base, root = pointer(kind), workspace_directory()
    base == root && return ""
    rel = relpath(base, root)
    return isabspath(rel) || startswith(rel, "..") ? base : rel
end

"""
    list_files(_)

Every file the UI may pick, as `{files: [{path, kind}], misplaced: [{path, kind, found}],
folders: {table, cards, filters}}` — `folders` being where each kind is listed from and saved
to, as the workspace sees it, for a form to say so.

Where a file sits says what it is offered as: a table under the data directory, a cards document
under the pipeline directory, a filters document under the filter directory, subfolders included,
each path relative to its own directory. Content still has to agree — a JSON is parsed to find
out, so a renamed document keeps its kind — and a file whose content says otherwise is reported
under `misplaced` rather than offered, so the Load tab can say why it is not there. Two kinds
sharing one directory (a flat workspace) list each file once, under the kind its content says.

What does not parse, is hidden, or is neither table nor document is not listed. A directory that
does not exist answers nothing for its kind and warns, rather than fail the whole listing.
"""
function list_files(::AbstractDict)
    files = @NamedTuple{path::String, kind::String}[]
    misplaced = @NamedTuple{path::String, kind::String, found::String}[]
    bases = Dict{String, Vector{Symbol}}()
    for kind in (:data, :pipeline, :filter)
        push!(get!(bases, pointer(kind), Symbol[]), kind)
    end
    for (base, kinds) in bases
        if !isdir(base)
            @warn "a directory of the workspace does not exist" base kinds
            continue
        end
        expected = [EXPECTED_KIND[kind] for kind in kinds]
        for path in files_under(base; except = collect(keys(bases)))
            found = file_kind(joinpath(base, path))
            isnothing(found) && continue
            if found in expected
                push!(files, (; path, kind = found))
            elseif length(kinds) < length(EXPECTED_KIND)
                push!(misplaced, (; path, kind = string(first(kinds)), found))
            end
        end
    end
    sort!(files, by = file -> (file.kind, file.path))
    sort!(misplaced, by = file -> (file.kind, file.path))
    folders = (; table = folder_label(:data), cards = folder_label(:pipeline), filters = folder_label(:filter))

    return function ()
        return (; files, misplaced, folders)
    end
end

"""
    read_document(spec)

A cards or filters document from the workspace: `{valid: true, document}`, or the failure
envelope every other route uses, with the server's sentence. Wrapped rather than returned bare,
so a client tells a reply from a failure by `valid` alone, never by guessing at a document's keys.

The counterpart of the browser's file dialog, which read a local file the server never saw and
showed the whole disk. `kind` is what the client expects: a filters file picked where cards
were asked for is refused here, with a sentence, rather than loaded into the wrong store.
"""
read_document(spec::AbstractDict) = read_document(spec, workspace_directory())

function read_document(spec::AbstractDict, base::AbstractString; what = "the workspace")
    path, kind = spec["path"], spec["kind"]
    full = resolve_in(base, path; what)
    isfile(full) || throw(ArgumentError("`$(path)` does not exist"))
    document = parse_document(full)
    document_kind(document) == kind || throw(ArgumentError("`$(path)` is not a $(kind) document"))
    return function ()
        return (; valid = true, document)
    end
end

"""
    write_document(spec)

Save a cards or filters document into the workspace, as indented JSON: `{valid: true, path}`
or the failure envelope. What keeps a document where it can be loaded again: a download leaves
the workspace, a save stays where `list-files` looks.

Refuses: a path outside the directory; a name that does not end in `.json` (TOML is read, not
written); a document whose shape is not `kind`'s; an existing file, unless `overwrite` is `true`.
A folder named on the way is made: a client that says where a file goes means it.
"""
write_document(spec::AbstractDict) = write_document(spec, workspace_directory())

function write_document(spec::AbstractDict, base::AbstractString; what = "the workspace")
    path, kind, document = spec["path"], spec["kind"], spec["document"]
    full = resolve_in(base, writable(path); what)
    lowercase(last(splitext(full))) == ".json" ||
        throw(ArgumentError("documents are saved as JSON: `$(path)` does not end in .json"))
    document_kind(document) == kind || throw(ArgumentError("this is not a $(kind) document"))
    (isfile(full) && get(spec, "overwrite", false) !== true) &&
        throw(ArgumentError("`$(path)` already exists"))
    return function ()
        mkpath(dirname(full))
        write(full, JSON.json(document; pretty = true))
        return (; valid = true, path)
    end
end

# The routes the form saves and reads with: one per kind, a path relative to that kind's own
# directory. They are the general routes with the directory fixed, which is what enforces the
# layout — the form never calls the general ones. The kind itself is implied, so a request
# carries no `kind`, and a path that spells the folder is turned away rather than nested.

const KIND_ROUTES = (
    ("pipeline", :pipeline, "cards", :document),
    ("filters", :filter, "filters", :document),
    ("model", :model, "model", :configuration),
    ("training", :training, "training", :configuration),
)

"""
    kind_path(kind::Symbol, path) -> String

`path` under the directory of `kind`, refusing one that leaves it or passes through a folder
named like the layout's own. The kind's folder is implied, so `pipeline/mine.json` would nest;
and another kind's name inside it would read as that kind's folder to anyone looking.
"""
function kind_path(kind::Symbol, path::AbstractString)
    segments = splitpath(normpath(path))
    folders = segments[1:(end - 1)]
    own = string(kind)
    if !isempty(folders) && first(folders) == own
        rest = joinpath(segments[2:end]...)
        throw(ArgumentError("`$(path)`: the `$(own)` folder is implied — name it `$(rest)`"))
    end
    reserved = findfirst(in(RESERVED), folders)
    isnothing(reserved) || throw(
        ArgumentError("`$(path)`: `$(folders[reserved])` is one of the layout's folder names, and cannot be a subfolder's")
    )
    length(segments) == 1 && first(segments) in RESERVED &&
        throw(ArgumentError("`$(path)` is one of the layout's folder names, not a file"))
    return resolve_in(pointer(kind), path; what = "the $(kind) directory")
end

struct KindHandler{F}
    handler::F
    kind::Symbol
    content::String
end

# A request for a kind route, rewritten as one for the general route it stands on: the kind
# filled in, and the path checked against the layout's folder names, resolved under the kind's
# directory and handed on relative to that directory, which becomes the general route's base.
function (kh::KindHandler)(spec::AbstractDict)
    (; handler, kind, content) = kh
    path = spec["path"]
    base = pointer(kind)
    full = kind_path(kind, path)
    spec′ = merge(spec, Dict("kind" => content, "path" => relpath(full, base)))
    what = "the $(kind) directory"
    return handler(spec′, base; what)
end

"""
    list_configurations(spec)

The model and training configurations a card may name, each with what it holds:
`{model: [{name, path, text, properties}], training: [...]}`. `name` is what a card's `type`
says — a path from the directory without the extension — and `text` is the file as written, for
a form to show beside the name rather than make the author open it.
"""
function list_configurations(::AbstractDict)
    describe(kind) = map(StreamlinerCore.available_streamliner_configs(pointer(kind), string(kind))) do name
        path = string(name, ".toml")
        full = joinpath(pointer(kind), path)
        parsed = TOML.parsefile(full)
        return (; name, path, text = read(full, String), properties = get(parsed, "properties", Any[]))
    end
    return function ()
        return (; model = describe(:model), training = describe(:training))
    end
end

"""
    read_configuration(spec)

A model or a training configuration: `{valid: true, text, parsed}` — the TOML as written, for
a form to show, and parsed, for it to read — or the failure envelope. `kind` is `model` or
`training` and must be what the file is.
"""
read_configuration(spec::AbstractDict) = read_configuration(spec, workspace_directory())

function read_configuration(spec::AbstractDict, base::AbstractString; what = "the workspace")
    path, kind = spec["path"], spec["kind"]
    full = resolve_in(base, path; what)
    isfile(full) || throw(ArgumentError("`$(path)` does not exist"))
    text = read(full, String)
    parsed = TOML.parse(text)
    configuration_kind(parsed) == kind || throw(ArgumentError("`$(path)` is not a $(kind) configuration"))
    return function ()
        return (; valid = true, text, parsed)
    end
end

"""
    write_configuration(spec)

Save a model or a training configuration as the TOML text given: `{valid: true, path}` or the
failure envelope. The text is parsed to check it is TOML and is the `kind` it is said to be;
it is written as sent, comments and all, since the file is what an author reads back.

Refuses as `write_document` does: a path outside the directory, a name not ending in `.toml`,
an existing file unless `overwrite` is `true`.
"""
write_configuration(spec::AbstractDict) = write_configuration(spec, workspace_directory())

function write_configuration(spec::AbstractDict, base::AbstractString; what = "the workspace")
    path, kind, text = spec["path"], spec["kind"], spec["text"]
    full = resolve_in(base, writable(path); what)
    lowercase(last(splitext(full))) == ".toml" ||
        throw(ArgumentError("configurations are saved as TOML: `$(path)` does not end in .toml"))
    parsed = try
        TOML.parse(text)
    catch err
        throw(ArgumentError("this is not TOML: $(sprint(showerror, err))"))
    end
    configuration_kind(parsed) == kind || throw(ArgumentError("this is not a $(kind) configuration"))
    (isfile(full) && get(spec, "overwrite", false) !== true) &&
        throw(ArgumentError("`$(path)` already exists"))
    mkpath(dirname(full))
    write(full, text)
    return function ()
        return (; valid = true, path)
    end
end

function load_files(spec::AbstractDict)
    # Checked here, not in `DataIngestion.parse_paths`, which joins `..` without looking and is
    # not ours to change: a client names files by the relative paths `list-files` gave it, and a
    # path that leaves the data directory is refused before anything is read.
    foreach(resolve_in_data_dir, spec["files"])
    return function ()
        DataIngestion.load_files(REPOSITORY[], spec)
        return DataIngestion.summarize(REPOSITORY[], "source")
    end
end

"""
    get_card_ir(spec)

The card descriptions a form is built from, in two halves: `cards`, the IR of every registered
card type, and `defs`, the shared vocabularies (`cols`, `nodes`, `groups`) the cards refer to.

The request carries the three vocabularies, since which nodes and groups can be referred to
depends on the document being edited. `include` names the halves wanted (default: both); `cards`
never changes while the server runs, so a client asks for `defs` alone after the first time.
"""
function get_card_ir(spec::AbstractDict)
    # An absent vocabulary is `nothing`, which means "unconstrained"; an empty list would mean
    # "nothing is allowed".
    maybe_strings(key) = haskey(spec, key) ? collect(String, spec[key]) : nothing
    # `include` is a list, or one string standing for a list of one. The string has to be wrapped
    # by hand: `Set{String}("defs")` would iterate its characters and throw.
    wanted = get(spec, "include", ["defs", "cards"])
    wanted isa AbstractString && (wanted = [wanted])
    wanted isa AbstractVector || throw(ArgumentError("`include` must be a string or a list of strings"))
    return function ()
        include = Set{String}(wanted)
        parts = StringDict()
        if "defs" in include
            variable_config = Pipelines.VariableConfig(
                nodes = maybe_strings("nodes"),
                groups = maybe_strings("groups"),
                cols = maybe_strings("cols"),
            )
            parts["defs"] = Pipelines.ir_definitions(variable_config)
        end
        if "cards" in include
            parts["cards"] = Dict{String, Any}(k => Pipelines.card_ir(k) for k in keys(Pipelines.CARD_SPECS))
        end
        return parts
    end
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
    # Four kinds of failure carry a JSON Pointer into the document, so the form can address the
    # control and, where it is known, offer a correction: a schema failure, a `through` chain the
    # pipeline refused to resolve, a product selection a card cannot write, and a transform for a
    # column a funnel does not have. Anything else — a cyclic graph, a
    # duplicate id, a binder error from DuckDB — has only its message.
    # Validation collects, so one schema failure and twenty arrive in the same shape; a chain
    # fails on the first one, so it arrives singular and is wrapped to match.
    issues = if exception isa Pipelines.SchemaValidationErrors
        Pipelines.issue_report(exception)
    elseif exception isa Union{Pipelines.ThroughError, Pipelines.ProductError, StreamlinerCore.TransformError}
        [Pipelines.issue_report(exception)]
    else
        []
    end
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

`empty_group_issues` has to answer before the pipeline is built (see there), and its answer must
not end the reply, or a document with an empty group *and* a broken card would name the group
only. The constructor validates the whole document before it builds anything, so a schema failure
arrives as `SchemaValidationErrors` whatever the groups hold; anything else it throws here is the
empty group's own consequence — a card built with no inputs — which `empty_group_issues` already
says in better words, and is dropped.
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
"The input graph contains at least one loop." — names nothing, so a client could only repeat it on
whichever card happened to be asked. The members are recoverable without sorting:
`Pipelines.dependency_graph` builds the graph and only the later topological sort throws, so the
strongly connected components with more than one vertex (or a self-edge) are exactly the loops.
Vertices are the nodes in document order, then the groups
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
    referable(nodes, groups)

For every card (by index) and group (by name), the nodes and groups it may refer to without
making a loop: all of them except itself and what depends on it. `nothing` when the dependency
graph cannot be built. Edges run from a dependency to what depends on it, so what depends on an
item is what can be reached from it.
"""
function referable(nodes::AbstractVector, groups::AbstractDict)
    graph, = try
        Pipelines.dependency_graph(nodes, groups)
    catch
        return nothing
    end
    n_nodes = length(nodes)
    ids = Pipelines.get_id.(nodes)
    group_names = collect(String, keys(groups))
    function allowed(vertex)
        free = findall(==(typemax(Int)), gdistances(graph, vertex))
        return (;
            nodes = String[ids[i] for i in free if i <= n_nodes],
            groups = String[group_names[i - n_nodes] for i in free if i > n_nodes],
        )
    end
    return (;
        nodes = [allowed(i) for i in 1:n_nodes],
        groups = Dict(name => allowed(n_nodes + j) for (j, name) in enumerate(group_names)),
    )
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
    model_issues(repository, pipeline, table) -> Vector

For each streamliner card of a built `pipeline`, whether its model can be built for what its
funnel feeds it, sized from `table`: one error at the card's `model` for each that cannot. Asked
by the probe, so Confirm turns the card red before a run trains anything, and by a run before it
trains.
"""
function model_issues(repository, pipeline, table::AbstractString)
    issues = []
    for (i, node) in enumerate(pipeline.nodes)
        card = Pipelines.get_card(node)
        card isa Pipelines.StreamlinerCard || continue
        # Only a model that does not fit its funnel is this check's to say. Anything else that
        # stops it building is left to the run, which reports every failure, rather than turning
        # a probe into an answer the form cannot render.
        issue = try
            Pipelines.model_issue(repository, card, table)
        catch exception
            exception isa Exception || rethrow()
            # TODO: do we really want to use `@error` here?
            @error "could not check whether the model of node $(i - 1) fits its funnel" exception =
                (exception, catch_backtrace())
            nothing
        end
        isnothing(issue) && continue
        push!(
            issues, (;
                pointer = "/nodes/$(i - 1)/card/model", reason = "model", severity = "error",
                found = nothing, allowed = nothing, missing = String[], related = String[],
                message = issue.message,
            )
        )
    end
    return issues
end

"""
    validate_card(spec)

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
function validate_card(spec::AbstractDict)
    maybe_strings(key)::Maybe{Vector{String}} = get(spec, key, nothing)
    variable_config = Pipelines.VariableConfig(
        nodes = maybe_strings("nodes"),
        groups = maybe_strings("groups"),
        cols = maybe_strings("cols"),
    )
    issues = Pipelines.card_issues(
        spec["card"], variable_config; base = get(spec, "base", "")
    )
    # An unknown card type has no schema to build, and a malformed request has no card. Both
    # are faults of what was sent, so they answer in the same envelope as everything else.
    return function ()
        return (; valid = isempty(issues), issues)
    end
end

"""
    empty_group_issues(groups)

One `pipeline`-kind issue per group that names no columns.

A group with an empty selector list is a legal document — `weather = []` constructs — and it
resolves to zero columns, so a card reading it is built with no inputs and dies inside the card
constructor with `UndefKeywordError: keyword argument args not assigned`. That message names the
implementation, not the mistake. Checked here, before the
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
at every layer and silently replaces the column. Overwriting can be meant, so
`severity = "warning"`: `valid` stays true and the run is
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
            push!(
                warnings, (;
                    pointer = "/nodes/$(i - 1)/card",
                    reason = "overwrites",
                    severity = "warning",
                    found = nothing,
                    allowed = nothing,
                    missing = String[],
                    related = String[],
                    message = join(("`$(name)` already exists and will be replaced" for name in clashing), "; "),
                )
            )
        end
        union!(seen, outputs)
    end
    return warnings
end

# FIXME: why does evaluate do `train_evaljoin`? Shouldn't we have separate `train` and `evaluate` endpoints?
"""
    evaluate_pipeline(spec)

Run an authored document. Takes the **group dialect** — `{filters, nodes, groups}`, with
selector-form variable fields — which is what the UI authors and what ExperimentTracking stores.

This route also takes the flat `{filters, cards}` shape, which it accepted before groups existed.
Both are kept: the UI authors the group dialect, and the group vocabulary is what its variable
picker exists to write.

## Probing before evaluation

Resolve a document without running it: which columns each node consumes and emits, and any it
references that nothing produces.

Construction is the cheap half of `evaluate-pipeline` — it resolves the group vocabulary and
validates against the schema — so a probe costs a graph walk and the source table's column names.
A streamliner card adds a check that its model can be built for its funnel: the table's column
types, one count per categorical column it names, and the model built once (`model_issues`).
Nothing is trained or materialised, so this is safe to call on every edit.

It reports rather than throws, for *every* way a document can be malformed rather than only
schema failures: a probe that answers 500 tells a form nothing it can render. Two nodes with no
`id`, for instance, both resolve to `""` and the dependency graph rejects them as duplicates —
an `ArgumentError`, which used to escape and leave the form silent.

Construction is pure document processing, so anything it raises is a fact about the document and
belongs in the response.

A schema failure additionally comes back as `issues` — a JSON Pointer into the document, the
failing keyword, and what would have been accepted — which is the vehicle a form needs to
address the offending control rather than print a sentence above it.
"""
function evaluate_pipeline(spec::AbstractDict)
    cols = colnames(REPOSITORY[], "source")
    groups = get(spec, "groups", Dict{String, Any}())
    _nodes = get(spec, "nodes", [])
    _filters = get(spec, "filters", [])
    may_refer = referable(_nodes, groups)

    # Before building: see `empty_group_issues` for why construction cannot report this itself.
    # The cards' own schema failures go out in the same answer (`card_schema_issues`), groups
    # first as in the document.
    empty = empty_group_issues(groups)
    if !isempty(empty)
        issues = vcat(empty, card_schema_issues(_nodes, groups, cols))
        failure = (;
            valid = false, kind = "pipeline", cols,
            errors = [issue.message for issue in issues], issues, referable = may_refer,
        )
        throw(DashiBase.StructuredException(StructUtils.make(StringDict, failure)))
    end

    # Running is the one step nothing static can vet. The probe answers everything that can be
    # known from the document alone, so what reaches here is a fault of the *data* — PCA asked for
    # more components than there are columns, a model that will not converge — and it surfaces only
    # by being run.
    filters = Filter.(_filters)
    pipeline = try
        Pipelines.Pipeline(_nodes, groups, cols)
    catch exception
        exception isa Exception || rethrow()
        # Always `pipeline`: this route resolves and never runs, so a fault it can see is by
        # construction a fault of the document. Deliberately not logged — the probe fires on every
        # edit, and most edits are documents the author has not finished writing yet.
        failure = (; build_failure(_nodes, groups, exception)..., cols, referable = may_refer)
        throw(DashiBase.StructuredException(StructUtils.make(StringDict, failure)))
    end
    # Sent with every answer below, so a picker offers an item only what cannot make a loop.

    absent = Dict(Pipelines.unproduced_references(pipeline, cols))
    # Sized from the loaded table; what earlier cards add is not in it yet and counts as one column.
    unfit = model_issues(REPOSITORY[], pipeline, "source")
    # `Pipelines.get_id` is the naming rule everything else uses; inventing an index here made
    # this the third answer to "what is this node called" in three files.
    ids = Pipelines.get_id.(_nodes)

    # The second source of pointed failures. An unproduced reference is addressed at *node*
    # granularity, not at the selector item that named it: resolution returns the column list and
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
            # What a `through` chain may do with this node, so a picker offers only chains the
            # pipeline would accept rather than guessing from which columns the node reads.
            through = Pipelines.through_options(node),
            # What a selection may narrow this node to: each named product with its columns.
            products = Pipelines.product_outputs(node),
            # What the card's lists resolved to, where a form has to spell them out — one row
            # per column to choose a transform for, say. Empty for most cards.
            lists = Pipelines.resolved_lists(Pipelines.get_card(node)),
        )
    end

    probe =
        (;
        valid = isempty(absent) && isempty(unfit), # TODO: shouldn't we throw earlier instead?
        # The probe's second way of being invalid, and the same kind as the first: a reference
        # nothing produces is a fault of the document, found by resolving rather than by running.
        kind = isempty(absent) && isempty(unfit) ? nothing : "pipeline",
        cols,
        nodes,
        referable = may_refer,
        source_vars = Pipelines.get_source_vars(pipeline),
        output_vars = Pipelines.get_output_vars(pipeline),
        errors = String[],
        # Always present, so a client can read one shape rather than branch on which half of the
        # route answered.
        # Errors first, then warnings: a client reading the list top-down sees what blocks the
        # run before what merely deserves a look.
        issues = vcat(unproduced_issues, unfit, overwrite_warnings(pipeline, cols)),
    )

    return ProbedThunk(probe) do
        orig = From("source") |> Partition() |> Define(ID_VAR[] => Agg.row_number())
        DataIngestion.select(REPOSITORY[], filters, orig => "selection")
        # The columns available *to* the pipeline, so the group API can validate references
        # against them rather than accepting a name that does not exist and failing later in SQL.
        p = Pipelines.train_evaljoin!(REPOSITORY[], pipeline, "selection", ID_VAR[])
        report = Pipelines.report(REPOSITORY[], pipeline.nodes)
        vs = Pipelines.visualize(REPOSITORY[], pipeline.nodes)
        visualization = stringify_visualization.(vs)
        graph = sprint(Pipelines.graphviz, p)
        # Recomputed: the pipeline has added its output columns since `available` was taken.
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        return (; valid = true, summaries, visualization, graph, report)
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

DuckDB's JSON writer emits bare `NaN` and `Infinity`, which are not JSON, so a page of a z-scored
constant column is unreadable to the browser. The cast happens in
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
    return Select(
        (
            name => (type in floaty ? Fun.case(Fun.isfinite(Get(name)), Get(name)) : Get(name))
                for (name, type) in zip(types.column_name, types.data_type)
        )...
    )
end

function fetch_data(stream, spec::AbstractDict)
    table = spec["processed"] ? "selection" : "source"
    ns = Set{String}(colnames(REPOSITORY[], table))
    limit::Int, offset::Int = spec["limit"], spec["offset"]
    sort_model::Vector = get(spec, "sortModel", [])
    sorters = Sorter.(sort_model)
    sorter_nodes = [Get(s.colname) |> s.sort for s in sorters if s.colname in ns]

    return function ()
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
end

function get_processed_data(stream, ::AbstractDict)
    return function ()
        mktempdir() do dir
            path = joinpath(dir, "processed-data.csv")
            export_table(REPOSITORY[], From("selection"), path)
            stream_data(stream, path, "text/csv")
        end
        return
    end
end
