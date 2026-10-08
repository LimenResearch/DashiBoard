# The parts of a workspace that need the server's own packages: sorting a plain folder into the
# layout, which has to tell a table from a document from a configuration, and loading the
# extensions a workspace names. Reading a workspace and building its environment are in
# `Workspace.jl`, which needs neither.

include("Workspace.jl")

using .Workspace: Workspace, KINDS, RESERVED, WORKSPACE_FILE, tidy_path, read_workspace_file,
    resolve_pointers, missing_directories, server_defaults, extension_sources, locate_sources,
    extension_environment, environment_path

# Sorting a plain folder into the layout.

# Which kind a loose file is — `"data"`, `"pipeline"`, `"filter"`, `"model"`, `"training"` — or
# `nothing` for a file that is none of them.
function destination_of(full::AbstractString)
    ext = lowercase(last(splitext(full)))
    if ext == ".toml"
        parsed = try
            TOML.parsefile(full)
        catch
            return nothing
        end
        kind = configuration_kind(parsed)
        isnothing(kind) || return kind
    end
    # A document may be written as TOML too, and is listed as one.
    kind = file_kind(full)
    kind == "table" && return "data"
    kind == "cards" && return "pipeline"
    kind == "filters" && return "filter"
    return nothing
end

# A free name in `folder` for `name`: the name itself, else `name-2`, `name-3`, …
function free_name(folder::AbstractString, name::AbstractString)
    ispath(joinpath(folder, name)) || return name
    stem, ext = splitext(name)
    n = 2
    while ispath(joinpath(folder, "$(stem)-$(n)$(ext)"))
        n += 1
    end
    return "$(stem)-$(n)$(ext)"
end

# What marks a folder as something other than a workspace: sorting one of these would scatter
# a project.
const NOT_A_WORKSPACE = ("Project.toml", "Manifest.toml", "package.json", "Cargo.toml", "pyproject.toml")

"""
    init_workspace(dir; io = stdout) -> (; placed, quarantined)

Sort the loose files at the root of `dir` into the layout, once, and say what went where.

A table goes to the data folder, a cards document to the pipeline folder, a filters document to
the filter folder, a model configuration to the model folder, a training one to the training
folder. The folders are the ones the workspace file names under `[directories]` when there is
one, and `data`, `pipeline`, `filter`, `model`, `training` otherwise. Anything else — a file of
no known kind, a folder that is not the layout's, a file whose name is already taken where it
belongs, a file standing where a folder must go — goes to `quarantine/` under its own name
(suffixed on a clash there too), so the root ends up holding only the layout and nothing is
lost or overwritten. Hidden entries and the workspace file stay. The folders are made, and a
`dashiboard.toml` with `[directories]` is written when there is none.

A folder that is plainly something else — a home directory, a code project — is refused: the
sorter moves everything it finds. Each move is reported as it is made.

`placed`, `quarantined` and `left` are `(name, where)` pairs; for the last two `where` is the
reason. A link is left where it is: moved, a relative one would point nowhere. Running it again
on a laid-out folder sorts whatever is loose and otherwise does nothing.
"""
function init_workspace(dir::AbstractString; io::IO = stdout)
    root = tidy_path(abspath(dir))
    isdir(root) || throw(ArgumentError("`$(dir)` is not a folder"))
    (root == tidy_path(homedir()) || dirname(root) == root) &&
        throw(ArgumentError("`$(root)` is not a workspace to sort: it is a home or a root directory"))
    marker = findfirst(name -> isfile(joinpath(root, name)), NOT_A_WORKSPACE)
    isnothing(marker) || throw(
        ArgumentError("`$(root)` holds a `$(NOT_A_WORKSPACE[marker])`: it looks like a project, not a workspace to sort")
    )

    # Where each kind goes: the folder the workspace file names, as written, else the kind's own.
    directories = get(read_workspace_file(root), "directories", Dict{String, Any}())
    folder_of = Dict(string(kind) => String(get(directories, string(kind), string(kind))) for kind in KINDS)
    folder_path(kind) = isabspath(folder_of[kind]) ? folder_of[kind] : joinpath(root, folder_of[kind])
    # The top-level names that are the layout's own, and so neither loose nor in its way.
    own = Set{String}(first(splitpath(folder)) for folder in values(folder_of) if !isabspath(folder))
    push!(own, "quarantine")

    placed, quarantined, left = Tuple{String, String}[], Tuple{String, String}[], Tuple{String, String}[]
    quarantine = joinpath(root, "quarantine")
    # A file standing where the quarantine itself goes is the first thing to set aside.
    if isfile(quarantine)
        held = joinpath(root, free_name(root, "quarantine.file"))
        mv(quarantine, held)
        mkpath(quarantine)
        mv(held, joinpath(quarantine, "quarantine"))
        push!(quarantined, ("quarantine", "a file where the `quarantine` folder goes"))
        println(io, "quarantine → quarantine/quarantine (a file where the `quarantine` folder goes)")
    end
    function put_aside(name, reason)
        mkpath(quarantine)
        target = free_name(quarantine, name)
        mv(joinpath(root, name), joinpath(quarantine, target))
        push!(quarantined, (name, reason))
        println(io, name, " → quarantine/", target == name ? "" : target, " (", reason, ")")
    end
    function loose(name)
        (startswith(name, ".") || name == WORKSPACE_FILE) && return false
        islink(joinpath(root, name)) || return true
        push!(left, (name, "a link, left where it is"))
        println(io, name, " (a link, left where it is)")
        return false
    end
    # What stands in the layout's way goes first: a file named like one of its folders, and a
    # folder that is not one of them. Only then can a file be placed where the folders go.
    entries = sort!(filter(loose, readdir(root)))
    for name in entries
        full = joinpath(root, name)
        if isdir(full)
            name in own || put_aside(name, "a folder that is not the layout's")
        elseif name in own
            put_aside(name, "a file where the `$(name)` folder goes")
        end
    end
    for name in entries
        full = joinpath(root, name)
        isfile(full) || continue
        kind = destination_of(full)
        if isnothing(kind)
            put_aside(name, "neither a table, a document nor a configuration")
            continue
        end
        folder = folder_path(kind)
        if ispath(joinpath(folder, name))
            put_aside(name, "`$(folder_of[kind])/$(name)` already exists")
            continue
        end
        mkpath(folder)
        mv(full, joinpath(folder, name))
        push!(placed, (name, folder_of[kind]))
        println(io, name, " → ", folder_of[kind], "/")
    end
    for kind in KINDS
        mkpath(folder_path(string(kind)))
    end
    file = joinpath(root, WORKSPACE_FILE)
    if !isfile(file)
        open(file, "w") do f
            TOML.print(f, Dict("directories" => folder_of))
        end
    end
    isempty(placed) && isempty(quarantined) && println(io, "nothing loose in ", root)
    return (; placed, quarantined, left)
end

# Extensions: loading what a workspace names, and what each contributed.

"""
    load_extensions(sources) -> Vector{Module}

The named extensions, loaded from the active environment — the one `extension_environment`
built, which the server is started in. Each must be a package exposing
`DEFAULT_PARSER::StreamlinerCore.Parser`, which is what it contributes.
"""
function load_extensions(sources::AbstractDict)
    return map(sort!(collect(String, keys(sources)))) do name
        mod = Base.require(Main, Symbol(name))
        isdefined(mod, :DEFAULT_PARSER) || throw(ArgumentError("extension `$(name)` has no `DEFAULT_PARSER`"))
        return mod
    end
end

# The registries of a parser, named in the singular as the provenance table keys them.
const REGISTRY_NAMES = (
    models = "model", layers = "layer", sigmas = "sigma", aggregators = "aggregator",
    metrics = "metric", regularizations = "regularization", optimizers = "optimizer",
    schedules = "schedule", stoppers = "stopper", devices = "device", funnels = "funnel",
    transforms = "transform",
)

"""
    provenance(modules) -> Dict{String, String}

Which extension contributed each registry entry: `"transform:double" => "TestExtension"`. What
lets a pipeline's download name exactly the extensions it needs.
"""
function provenance(modules::AbstractVector)
    table = Dict{String, String}()
    for mod in modules
        parser = getfield(mod, :DEFAULT_PARSER)
        for (field, registry) in pairs(REGISTRY_NAMES)
            hasproperty(parser, field) || continue
            for key in keys(getproperty(parser, field))
                table[string(registry, ':', key)] = string(nameof(mod))
            end
        end
    end
    return table
end
