# A workspace: the directory the server is launched against, where each kind of file is, and the
# extensions it names.
#
# The layout is the default answer to the directories Pipelines' `@with` block already takes —
# `MODEL_DIR`, `TRAINING_DIR` — and DataIngestion's `DATA_DIR`; nothing here replaces them. A
# `dashiboard.toml` at the root can say otherwise, and a flag can say otherwise again. In that
# order: flag, file, the conventional folder when it exists, the root.
#
# A module of its own, on the standard library alone: the launcher reads a workspace and builds
# the environment its extensions need *before* the server's packages are loaded, so that the
# server starts inside that environment and what is loaded is what was resolved.
module Workspace

using TOML: TOML
using Pkg: Pkg

const KINDS = (:data, :pipeline, :filter, :model, :training)

# Folder names that are the layout's own, and so not a subfolder's inside a kind's directory.
const RESERVED = (string.(KINDS)..., "quarantine")

const WORKSPACE_FILE = "dashiboard.toml"

# Where this package is: the checkout the environment's own packages are taken from.
const PACKAGE_DIR = dirname(@__DIR__)

# A path with no trailing separator, so that one folder written two ways is one folder.
function tidy_path(path::AbstractString)
    tidy = normpath(path)
    return length(tidy) > 1 && endswith(tidy, Base.Filesystem.path_separator) ? chop(tidy) : tidy
end

# What a workspace file may say, checked before any of it is used: a table the launcher does not
# know, or a value of the wrong kind, would otherwise be skipped or fail somewhere unrelated.
function check_workspace_file(file::AbstractDict, path::AbstractString)
    refuse(what) = throw(ArgumentError("`$(path)`: $(what)"))
    for key in keys(file)
        key in ("directories", "extensions", "server") || refuse("no such table as `[$(key)]`; there are `[directories]`, `[extensions]` and `[server]`")
    end
    for name in ("directories", "extensions", "server")
        get(file, name, Dict{String, Any}()) isa AbstractDict || refuse("`$(name)` is a table")
    end
    for (kind, dir) in get(file, "directories", Dict{String, Any}())
        Symbol(kind) in KINDS || refuse("`[directories]` has no `$(kind)`: the kinds are $(join(KINDS, ", "))")
        dir isa AbstractString || refuse("`[directories].$(kind)` is a path, written as a string")
    end
    for (name, source) in get(file, "extensions", Dict{String, Any}())
        source isa AbstractDict || refuse("`[extensions].$(name)` is a table with a `path` or a `url`, as in `{ path = \"…\" }`")
        (haskey(source, "path") || haskey(source, "url")) || refuse("`[extensions].$(name)` needs a `path` or a `url`")
        all(v -> v isa AbstractString, values(source)) || refuse("`[extensions].$(name)` holds strings")
        issubset(keys(source), ("path", "url", "rev")) || refuse("`[extensions].$(name)` takes `path`, or `url` and `rev`")
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
A file that says something the launcher does not read — a misspelt table, a value of the wrong
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
`fell_back` lists the kinds that landed on the root, for the launcher to warn about. A
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
flag or by the file — can be missing, and a server on it would fail on its first question, so
the launcher says so instead.
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

# Extensions: the packages a workspace names and where they are.

# One `Name=source` entry of the command line. A source is a path, or the address of a git
# remote with, optionally, `@rev` after it. An `@` is part of the address unless it comes after
# the last `/` or `:` — `ssh://git@host/Org/X.jl@v2` names the revision `v2`, and
# `git@host:Org/X.jl` names none.
function parse_extension(entry::AbstractString)
    occursin('=', entry) || throw(ArgumentError("`--extensions` takes `Name=path` or `Name=url@rev`; `$(entry)` names no source"))
    name, source = split(entry, '='; limit = 2)
    remote = occursin("://", source) || occursin(r"^[\w.-]+@[\w.-]+:", source)
    # Typed where the user stands, like a directory flag.
    remote || return String(name) => Dict{String, Any}("path" => abspath(String(source)))
    at = findlast('@', source)
    address_end = something(findlast(c -> c == '/' || c == ':', source), 0)
    return String(name) => if !isnothing(at) && at > address_end
        Dict{String, Any}("url" => String(source[1:prevind(source, at)]), "rev" => String(source[nextind(source, at):end]))
    else
        Dict{String, Any}("url" => String(source))
    end
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
    return Dict{String, Dict{String, Any}}(parse_extension(entry) for entry in split(flag, ','; keepempty = false))
end

"""
    locate_sources(workspace, sources) -> Dict

`sources` with every `path` made absolute: one written relative is relative to the workspace, as
a `[directories]` entry is. A source that is a remote is left as written. What the launcher
resolves and loads from, and what a downloaded pipeline names, since its folder will be
somewhere else.
"""
function locate_sources(workspace::AbstractString, sources::AbstractDict)
    root = normpath(abspath(workspace))
    return Dict{String, Dict{String, Any}}(
        name => haskey(source, "path") ?
            merge(Dict{String, Any}(source), Dict{String, Any}("path" => normpath(joinpath(root, expanduser(source["path"]))))) :
            Dict{String, Any}(source)
            for (name, source) in pairs(sources)
    )
end

# This package's own packages, where the checkout keeps them: the dependencies its project names
# by a path that is there. A package installed from a registry has none.
function own_packages()
    sources = get(TOML.parsefile(joinpath(PACKAGE_DIR, "Project.toml")), "sources", Dict{String, Any}())
    paths = String[normpath(joinpath(PACKAGE_DIR, source["path"])) for source in values(sources) if haskey(source, "path")]
    return filter!(isdir, paths)
end

# What an environment was built from: the sources, and the project files of everything taken by
# path — an extension's and this checkout's own — since a dependency added to one of them asks
# for a new resolution as much as a new source does.
function sources_stamp(sources::AbstractDict)
    paths = vcat(PACKAGE_DIR, own_packages(), String[source["path"] for source in values(sources) if haskey(source, "path")])
    projects = [path => (isfile(joinpath(path, "Project.toml")) ? hash(read(joinpath(path, "Project.toml"))) : UInt(0)) for path in sort!(paths)]
    # The leading number is the stamp's format: changing it rebuilds every workspace's environment.
    return string("4:", hash((sort!([k => sort!(collect(v)) for (k, v) in pairs(sources)]; by = first), projects)))
end

"""
    environment_path(workspace) -> String

Where the environment of a workspace's extensions is kept: `<workspace>/.dashiboard/env`.
"""
environment_path(workspace::AbstractString) = joinpath(tidy_path(abspath(workspace)), ".dashiboard", "env")

"""
    extension_environment(workspace, sources; io = stderr) -> String

The Julia project the server runs in when `workspace` names extensions: this package and its
own packages, each from where this checkout keeps them, and each extension from the source
given — `path`, or `url` with an optional `rev`, the forms Julia's `[sources]` takes — resolved
together, so one version of every package serves them all. Built when the sources differ from
the last launch, and afresh rather than amended; left alone otherwise. An extension that cannot
be resolved stops here with an error naming it.
"""
function extension_environment(workspace::AbstractString, sources::AbstractDict; io::IO = stderr)
    env = environment_path(workspace)
    sources = locate_sources(workspace, sources)
    stamp_file = joinpath(env, "sources.stamp")
    stamp = sources_stamp(sources)
    isfile(stamp_file) && read(stamp_file, String) == stamp && isfile(joinpath(env, "Manifest.toml")) && return env
    # Built afresh rather than amended: what the sources no longer name must not be carried
    # along, and a half-made environment must not be taken for a finished one.
    rm(env; recursive = true, force = true)
    mkpath(env)
    previous = Base.active_project()
    try
        Pkg.activate(env; io)
        # The server's own packages first, each from where this one is: an extension names
        # whatever version it was written against, and two versions of one package cannot
        # both be the one the server runs.
        Pkg.develop([Pkg.PackageSpec(path = path) for path in vcat(PACKAGE_DIR, own_packages())]; io)
        for (name, source) in sort!(collect(pairs(sources)); by = first)
            spec = if haskey(source, "path")
                Pkg.PackageSpec(path = source["path"])
            elseif haskey(source, "url")
                haskey(source, "rev") ? Pkg.PackageSpec(url = source["url"], rev = source["rev"]) : Pkg.PackageSpec(url = source["url"])
            else
                throw(ArgumentError("extension `$(name)` needs a `path` or a `url`"))
            end
            try
                haskey(source, "path") ? Pkg.develop(spec; io) : Pkg.add(spec; io)
            catch err
                throw(ArgumentError("extension `$(name)` could not be resolved from $(source): $(sprint(showerror, err))"))
            end
        end
        Pkg.instantiate(; io)
        write(stamp_file, stamp)
    finally
        isnothing(previous) || Pkg.activate(previous; io = devnull)
    end
    return env
end

end # module Workspace
