# A workspace: the directory the server is launched against, where each kind of file is, and the
# extensions it names.
#
# The layout is the default answer to the directories Pipelines' `@with` block already takes —
# `MODEL_DIR`, `TRAINING_DIR` — and DataIngestion's `DATA_DIR`; nothing here replaces them. A
# `dashiboard.toml` at the root can say otherwise. In that order: the file, the conventional
# folder when it exists, the root.
#
# A module of its own: reading a workspace needs the standard library alone.
module WorkspaceUtils

using TOML: TOML

const KINDS = (:data, :pipeline, :filter, :model, :training)

# Folder names that are the layout's own, and so not a subfolder's inside a kind's directory.
const RESERVED = (string.(KINDS)..., "quarantine")

const WORKSPACE_FILE = "dashiboard.toml"

# A path with no trailing separator, so that one folder written two ways is one folder.
function tidy_path(path::AbstractString)
    tidy = normpath(path)
    return length(tidy) > 1 && endswith(tidy, Base.Filesystem.path_separator) ? chop(tidy) : tidy
end

# What a workspace file may say, checked before any of it is used: a table DashiBoard does not
# know, or a value of the wrong kind, would otherwise be skipped or fail somewhere unrelated.
function check_workspace_file(file::AbstractDict, path::AbstractString)
    refuse(what) = throw(ArgumentError("`$(path)`: $(what)"))
    for key in keys(file)
        key in ("dashiboard", "directories", "extensions", "server") || refuse("no such table as `[$(key)]`; there are `[dashiboard]`, `[directories]`, `[extensions]` and `[server]`")
    end
    for name in ("dashiboard", "directories", "extensions", "server")
        get(file, name, Dict{String, Any}()) isa AbstractDict || refuse("`$(name)` is a table")
    end
    for (kind, dir) in get(file, "directories", Dict{String, Any}())
        Symbol(kind) in KINDS || refuse("`[directories]` has no `$(kind)`: the kinds are $(join(KINDS, ", "))")
        dir isa AbstractString || refuse("`[directories].$(kind)` is a path, written as a string")
    end
    # Every source is a release, pinned: a `url` and a `rev`, never a `path`, whose code could
    # change under a Manifest resolved once.
    pinned(source) = source isa AbstractDict && Set(keys(source)) == Set(("url", "rev")) &&
        all(v -> v isa AbstractString, values(source))
    haskey(file, "dashiboard") && !pinned(file["dashiboard"]) &&
        refuse("`[dashiboard]` takes a `url` and a `rev` (a tag or a commit)")
    for (name, source) in get(file, "extensions", Dict{String, Any}())
        pinned(source) || refuse("`[extensions].$(name)` takes a `url` and a `rev` (a tag or a commit), as in `{ url = \"…\", rev = \"v1.0.0\" }`")
    end
    server = get(file, "server", Dict{String, Any}())
    issubset(keys(server), ("host", "port")) || refuse("`[server]` takes `host` and `port`")
    get(server, "host", "") isa AbstractString || refuse("`[server].host` is a string")
    get(server, "port", 0) isa Integer || refuse("`[server].port` is a number")
    return file
end

"""
    read_workspace_file(workspace) -> Dict

The parsed `dashiboard.toml` at the root of `workspace`, or an empty `Dict` when there is none.
A file that says something DashiBoard does not read — a misspelt table, a value of the wrong
kind — is refused, naming the entry.
"""
function read_workspace_file(workspace::AbstractString)
    path = joinpath(workspace, WORKSPACE_FILE)
    return isfile(path) ? check_workspace_file(TOML.parsefile(path), path) : Dict{String, Any}()
end

"""
    resolve_pointers(workspace, file, flags) -> (; dirs, fell_back)

Where each kind of file is, as absolute paths keyed by kind: a `<kind>_dir` entry of `flags`
first, then the `[directories]` entry of `file`, then `<workspace>/<kind>` when that folder
exists, then the workspace itself. A relative flag is read from the working directory — it is
what the user typed where they stand — and a relative entry of the file from the workspace.
`fell_back` lists the kinds that landed on the root, for a launch to warn about. A
`[directories]` key that is not a kind is refused rather than ignored, so a misspelt one does
not silently fall back.
"""
function resolve_pointers(workspace::AbstractString, file::AbstractDict, flags::AbstractDict)
    root = tidy_path(abspath(workspace))
    directories = get(file, "directories", Dict{String, Any}())
    for key in keys(directories)
        Symbol(key) in KINDS || throw(ArgumentError("`[directories]` has no `$(key)`: the kinds are $(join(KINDS, ", "))"))
    end
    from_file(path) = tidy_path(isabspath(path) ? path : joinpath(root, path))
    from_flag(path) = tidy_path(abspath(path))
    dirs = Dict{Symbol, String}()
    fell_back = Symbol[]
    for kind in KINDS
        flag = get(flags, string(kind, "_dir"), nothing)
        entry = get(directories, string(kind), nothing)
        conventional = joinpath(root, string(kind))
        dirs[kind] = if !isnothing(flag)
            from_flag(flag)
        elseif !isnothing(entry)
            from_file(entry)
        elseif isdir(conventional)
            tidy_path(conventional)
        else
            push!(fell_back, kind)
            root
        end
    end
    return (; dirs, fell_back)
end

"""
    missing_directories(dirs) -> Vector{Pair{Symbol, String}}

The kinds whose directory is not there, with the path. Only a directory that was named — by a
flag or by the file — can be missing, and a server on it would fail on its first question, so a
launch says so instead.
"""
missing_directories(dirs::AbstractDict) = Pair{Symbol, String}[kind => dirs[kind] for kind in KINDS if !isdir(dirs[kind])]

"""
    server_defaults(file) -> (; host, port)

What `[server]` in a workspace file says, `nothing` where it says nothing.
"""
function server_defaults(file::AbstractDict)
    server = get(file, "server", Dict{String, Any}())
    return (; host = get(server, "host", nothing), port = get(server, "port", nothing))
end

"""
    dashiboard_source(file) -> (; url, rev)

Where a deployment's DashiBoard comes from: the `[dashiboard]` table, which install requires and a
bundled workspace may leave out.
"""
function dashiboard_source(file::AbstractDict)
    haskey(file, "dashiboard") || throw(ArgumentError("no `[dashiboard]` table: name DashiBoard's `url` and `rev`"))
    source = file["dashiboard"]
    return (; url = String(source["url"]), rev = String(source["rev"]))
end

"""
    extension_sources(file) -> Dict{String, Dict{String, Any}}

The extensions a workspace names, each with its `url` and `rev`, as the `[extensions]` table says.
"""
function extension_sources(file::AbstractDict)
    table = get(file, "extensions", Dict{String, Any}())
    return Dict{String, Dict{String, Any}}(name => Dict{String, Any}(source) for (name, source) in pairs(table))
end

end # module WorkspaceUtils
