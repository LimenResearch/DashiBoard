# A workspace: the directory the server is launched against, and where each kind of file is.
#
# The layout is the default answer to the directories Pipelines' `@with` block already takes —
# `MODEL_DIR`, `TRAINING_DIR` — and DataIngestion's `DATA_DIR`; nothing here replaces them. A
# `dashiboard.toml` at the root can say otherwise, and a flag can say otherwise again. In that
# order: flag, file, the conventional folder when it exists, the root.

const KINDS = (:data, :pipeline, :filter, :model, :training)

# Folder names no path under a kind's directory may start with: they are the layout's own.
const RESERVED = (string.(KINDS)..., "quarantine")

const WORKSPACE_FILE = "dashiboard.toml"

"""
    read_workspace_file(workspace) -> Dict

The parsed `dashiboard.toml` at the root of `workspace`, or an empty `Dict` when there is none.
"""
function read_workspace_file(workspace::AbstractString)
    path = joinpath(workspace, WORKSPACE_FILE)
    return isfile(path) ? TOML.parsefile(path) : Dict{String, Any}()
end

"""
    resolve_pointers(workspace, file, flags) -> (; dirs, fell_back)

Where each kind of file is, as absolute paths keyed by kind: a `<kind>_dir` entry of `flags`
first, then the `[directories]` entry of `file`, then `<workspace>/<kind>` when that folder
exists, then the workspace itself. `fell_back` lists the kinds that landed on the root, for the
launcher to warn about. A `[directories]` key that is not a kind is refused rather than ignored,
so a misspelt one does not silently fall back.
"""
function resolve_pointers(workspace::AbstractString, file::AbstractDict, flags::AbstractDict)
    root = normpath(abspath(workspace))
    directories = get(file, "directories", Dict{String, Any}())
    for key in keys(directories)
        Symbol(key) in KINDS || throw(ArgumentError("`[directories]` has no `$(key)`: the kinds are $(join(KINDS, ", "))"))
    end
    resolve(path) = isabspath(path) ? normpath(path) : normpath(joinpath(root, path))
    dirs = Dict{Symbol, String}()
    fell_back = Symbol[]
    for kind in KINDS
        flag = get(flags, string(kind, "_dir"), nothing)
        entry = get(directories, string(kind), nothing)
        conventional = joinpath(root, string(kind))
        dirs[kind] = if !isnothing(flag)
            resolve(flag)
        elseif !isnothing(entry)
            resolve(entry)
        elseif isdir(conventional)
            normpath(conventional)
        else
            push!(fell_back, kind)
            root
        end
    end
    return (; dirs, fell_back)
end

"""
    server_defaults(file) -> (; host, port)

What `[server]` in a workspace file says, `nothing` where it says nothing.
"""
function server_defaults(file::AbstractDict)
    server = get(file, "server", Dict{String, Any}())
    return (; host = get(server, "host", nothing), port = get(server, "port", nothing))
end

"""
    extension_sources(file, flags) -> Dict{String, Dict{String, Any}}

The extensions to register and where each is, in the forms Julia's `[sources]` takes: the
`[extensions]` table of the workspace file, or the `--extensions` flag when given, written
`Name=path` or `Name=url@rev`, comma-separated. The flag replaces the table rather than adding to
it, so a command line says all of what is loaded.
"""
function extension_sources(file::AbstractDict, flags::AbstractDict)
    flag = get(flags, "extensions", nothing)
    if isnothing(flag)
        table = get(file, "extensions", Dict{String, Any}())
        return Dict{String, Dict{String, Any}}(name => Dict{String, Any}(source) for (name, source) in pairs(table))
    end
    sources = Dict{String, Dict{String, Any}}()
    for entry in split(flag, ','; keepempty = false)
        name, source = split(entry, '='; limit = 2)
        sources[String(name)] = if occursin("://", source)
            url, rev = occursin('@', source) ? split(source, '@'; limit = 2) : (source, "main")
            Dict{String, Any}("url" => String(url), "rev" => String(rev))
        else
            Dict{String, Any}("path" => String(source))
        end
    end
    return sources
end
