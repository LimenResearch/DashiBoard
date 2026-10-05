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

# Sorting a plain folder into the layout.

# Where a loose file belongs, by what it is: the folder's name, or `nothing` for a file that is
# none of the kinds.
function destination_of(full::AbstractString)
    ext = lowercase(last(splitext(full)))
    if ext == ".toml"
        parsed = try
            TOML.parsefile(full)
        catch
            return nothing
        end
        kind = configuration_kind(parsed)
        isnothing(kind) && return nothing
        return kind
    end
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

"""
    init_workspace(dir; io = stdout) -> (; placed, quarantined)

Sort the loose files at the root of `dir` into the layout, once, and say what went where.

A table goes to `data/`, a cards document to `pipeline/`, a filters document to `filter/`, a
model configuration to `model/`, a training one to `training/`. Anything else — a file of no
known kind, a folder that is not the layout's, a file whose name is already taken where it
belongs, a file standing where a folder must go — goes to `quarantine/` under its own name
(suffixed on a clash there too), so the root ends up holding only the layout and nothing is
lost or overwritten. Hidden entries and the workspace file stay. The folders are made, and a
`dashiboard.toml` with `[directories]` is written when there is none.

`placed` and `quarantined` are `(name, where)` pairs; `quarantined`'s `where` is the reason.
Running it again on a laid-out folder sorts whatever is loose and otherwise does nothing.
"""
function init_workspace(dir::AbstractString; io::IO = stdout)
    root = normpath(abspath(dir))
    placed, quarantined = Tuple{String, String}[], Tuple{String, String}[]
    quarantine = joinpath(root, "quarantine")
    function put_aside(name, reason)
        mkpath(quarantine)
        target = free_name(quarantine, name)
        mv(joinpath(root, name), joinpath(quarantine, target))
        push!(quarantined, (name, reason))
    end
    loose(name) = !(startswith(name, ".") || name == WORKSPACE_FILE)
    # What stands in the layout's way goes first: a file named like one of its folders, and a
    # folder that is not one of them. Only then can a file be placed where the folders go.
    for name in sort!(filter(loose, readdir(root)))
        full = joinpath(root, name)
        if isdir(full)
            name in RESERVED || put_aside(name, "a folder that is not the layout's")
        elseif name in RESERVED
            put_aside(name, "a file where the `$(name)` folder goes")
        end
    end
    for name in sort!(filter(loose, readdir(root)))
        full = joinpath(root, name)
        isdir(full) && continue
        destination = destination_of(full)
        if isnothing(destination)
            put_aside(name, "neither a table, a document nor a configuration")
            continue
        end
        folder = joinpath(root, destination)
        if ispath(joinpath(folder, name))
            put_aside(name, "`$(destination)/$(name)` already exists")
            continue
        end
        mkpath(folder)
        mv(full, joinpath(folder, name))
        push!(placed, (name, destination))
    end
    for kind in KINDS
        mkpath(joinpath(root, string(kind)))
    end
    file = joinpath(root, WORKSPACE_FILE)
    if !isfile(file)
        open(file, "w") do f
            TOML.print(f, Dict("directories" => Dict(string(kind) => string(kind) for kind in KINDS)))
        end
    end
    for (name, where) in placed
        println(io, name, " → ", where, "/")
    end
    for (name, reason) in quarantined
        println(io, name, " → quarantine/ (", reason, ")")
    end
    isempty(placed) && isempty(quarantined) && println(io, "nothing loose in ", root)
    return (; placed, quarantined)
end

# Extensions: the packages a workspace names, where they are, and what they contributed.

"""
    locate_sources(workspace, sources) -> Dict

`sources` with every `path` made absolute: one written relative is relative to the workspace, as
a `[directories]` entry is. What the launcher resolves and loads from, and what a downloaded
pipeline names, since its folder will be somewhere else.
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

# The hash of a sources table, kept beside the environment so that unchanged sources do not
# resolve again.
sources_stamp(sources::AbstractDict) = string("2:", hash(sort!([k => sort!(collect(v)) for (k, v) in pairs(sources)]; by = first)))

# DashiBoard's own packages, where this checkout keeps them: the dependencies its project
# names by path.
function own_packages()
    root = pkgdir(DashiBoard)
    sources = get(TOML.parsefile(joinpath(root, "Project.toml")), "sources", Dict{String, Any}())
    return String[normpath(joinpath(root, source["path"])) for source in values(sources) if haskey(source, "path")]
end

"""
    extension_environment(workspace, sources; io = stderr) -> String

The Julia project the server runs in when `workspace` names extensions:
`<workspace>/.dashiboard/env/`, holding DashiBoard itself, developed from where this one is, and
each extension from the source given — `path`, or `url` with `rev`, the forms Julia's `[sources]`
takes. Resolved and instantiated when the sources differ from the last launch, left alone
otherwise. An extension that cannot be resolved stops here with an error naming it.
"""
function extension_environment(workspace::AbstractString, sources::AbstractDict; io::IO = stderr)
    env = joinpath(normpath(abspath(workspace)), ".dashiboard", "env")
    sources = locate_sources(workspace, sources)
    stamp_file = joinpath(env, "sources.stamp")
    stamp = sources_stamp(sources)
    isfile(stamp_file) && read(stamp_file, String) == stamp && isfile(joinpath(env, "Manifest.toml")) && return env
    mkpath(env)
    previous = Base.active_project()
    try
        Pkg.activate(env; io)
        # The server's own packages first, each from where this one is: an extension names
        # whatever version it was written against, and two versions of one package cannot
        # both be the one the server runs.
        Pkg.develop([Pkg.PackageSpec(path = path) for path in vcat(pkgdir(DashiBoard), own_packages())]; io)
        for (name, source) in sort!(collect(pairs(sources)); by = first)
            spec = if haskey(source, "path")
                Pkg.PackageSpec(path = source["path"])
            elseif haskey(source, "url")
                Pkg.PackageSpec(url = source["url"], rev = get(source, "rev", "main"))
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

"""
    load_extensions(sources; env) -> Vector{Module}

The named extensions, loaded from `env` — the environment `extension_environment` built, made
the active one — or from the active environment when none is given. Each must be a package
exposing `DEFAULT_PARSER::StreamlinerCore.Parser`, which is what it contributes.
"""
function load_extensions(sources::AbstractDict; env::Union{AbstractString, Nothing} = nothing)
    isnothing(env) || Pkg.activate(env; io = devnull)
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
    loaders = "loader", transforms = "transform",
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
