# A deployment: a folder installed once by `bin/install.jl` and launched any number of times.
# Install resolves `dashiboard.toml` into `.dashiboard/` — a clone of DashiBoard, a Project and
# Manifest, a private depot — and hands over to `install_deployment`, which writes what a launch
# runs. A launch never resolves: `serve_deployment` serves what was resolved, or says what changed.

const DEPLOYMENT_DIR = ".dashiboard"

deployment_path(deploy::AbstractString, parts::AbstractString...) = joinpath(deploy, DEPLOYMENT_DIR, parts...)

"""
    serve_script(extensions) -> String

`serve.jl`: DashiBoard and exactly the extensions resolved with it, loaded by name, then served.
"""
function serve_script(extensions::AbstractVector{<:AbstractString})
    names = sort!(collect(String, extensions))
    return join(
        [
            "# Written by install: loads DashiBoard and the extensions resolved with it, and serves.",
            "using DashiBoard",
            ("using $(name)" for name in names)...,
            "DashiBoard.serve_deployment(dirname(@__DIR__), Module[$(join(names, ", "))])",
        ], "\n"
    ) * "\n"
end

"""
    launch_script(julia = the running Julia) -> String

`launch.sh`: the Julia install ran with, the deployment's project and its private depot, and
nothing inherited that would point it elsewhere.
"""
function launch_script(julia::AbstractString = joinpath(Sys.BINDIR, "julia"))
    # Single-quoted, so nothing in the path is read by the shell.
    quoted = "'" * replace(julia, "'" => "'\\''") * "'"
    return """
    #!/bin/sh
    # Written by install: the deployment's own project, depot and Julia.
    here="\$(cd "\$(dirname "\$0")" && pwd)"
    julia=$(quoted)
    # The Julia that compiled the depot; without it nothing installed can load.
    [ -x "\$julia" ] || { echo "the Julia this deployment was installed with, \$julia, is gone: run install.jl <deploy> --update all" >&2; exit 1; }
    unset JULIA_LOAD_PATH JULIA_PROJECT
    JULIA_DEPOT_PATH="\$here/depot" exec "\$julia" --startup-file=no --project="\$here" "\$here/serve.jl"
    """
end

"""
    deployment_record(file, commit) -> Dict

What install resolved, for a launch to compare against: DashiBoard's source and the clone's
commit, the extensions, and the Julia that compiled them.
"""
function deployment_record(file::AbstractDict, commit::AbstractString)
    source = dashiboard_source(file)
    return Dict{String, Any}(
        "dashiboard" => Dict{String, Any}("url" => source.url, "rev" => source.rev, "commit" => commit),
        "extensions" => extension_sources(file),
        "julia" => string(VERSION),
    )
end

"""
    record_mismatches(record, file, commit, julia = the running Julia) -> Vector{String}

One sentence per way the deployment differs from what install resolved, each naming the update
that resolves it again. Empty when a launch may serve.
"""
function record_mismatches(record::AbstractDict, file::AbstractDict, commit::AbstractString, julia::AbstractString = string(VERSION))
    problems = String[]
    was = record["dashiboard"]
    source = dashiboard_source(file)
    (source.url, source.rev) == (was["url"], was["rev"]) || push!(
        problems,
        "`[dashiboard]` is $(source.url) at $(source.rev), installed from $(was["url"]) at $(was["rev"]): run `install.jl <deploy> --update all`"
    )
    commit == was["commit"] || push!(
        problems, "the DashiBoard clone is at $(commit), installed at $(was["commit"]): run `install.jl <deploy> --update all`"
    )
    extension_sources(file) == record["extensions"] ||
        push!(problems, "`[extensions]` changed since install: run `install.jl <deploy> --update extensions`")
    julia == record["julia"] || push!(
        problems, "Julia is $(julia), the deployment was installed with $(record["julia"]): run `install.jl <deploy> --update all`"
    )
    return problems
end

"""
    check_extensions_update(record, file, commit, julia = the running Julia)

Refuse to move only the extensions when DashiBoard's source, its clone or Julia changed too: the
record would then name a release that was never installed.
"""
function check_extensions_update(record::AbstractDict, file::AbstractDict, commit::AbstractString, julia::AbstractString = string(VERSION))
    was = record["dashiboard"]
    source = dashiboard_source(file)
    unchanged = (source.url, source.rev, commit, julia) == (was["url"], was["rev"], was["commit"], record["julia"])
    unchanged || throw(ArgumentError("DashiBoard or Julia changed since install, which only a full update adopts: run `install.jl <deploy> --update all`"))
    return nothing
end

# The clone's commit, read from its detached `HEAD`, so a launch needs no git.
clone_commit(deploy::AbstractString) = strip(read(deployment_path(deploy, "DashiBoard", ".git", "HEAD"), String))

"""
    install_deployment(deploy; update)

The part of install that needs the release's own code, run by `bin/install.jl` inside the resolved
environment: add the extensions, lay the folders out, write `serve.jl`, `launch.sh` and the record.
`update` is `:none` for a first install, `:all` after a full re-resolve, `:extensions` to move only
the extensions while everything else in the Manifest stays.
"""
function install_deployment(deploy::AbstractString; update::Symbol)
    file = read_workspace_file(deploy)
    dashiboard_source(file)
    extensions = extension_sources(file)
    specs = [Pkg.PackageSpec(; name, url = source["url"], rev = source["rev"]) for (name, source) in extensions]
    if update in (:none, :all)
        isempty(specs) || Pkg.add(specs)
    elseif update === :extensions
        record = TOML.parsefile(deployment_path(deploy, "record.toml"))
        check_extensions_update(record, file, clone_commit(deploy))
        was = record["extensions"]
        dropped = setdiff(keys(was), keys(extensions))
        isempty(dropped) || Pkg.rm(collect(dropped))
        try
            isempty(specs) || Pkg.add(specs; preserve = Pkg.PRESERVE_ALL)
        catch err
            throw(ArgumentError("the extensions could not be added keeping everything else installed as it is; if they need other versions of DashiBoard's dependencies, run `install.jl $(deploy) --update all` ($(sprint(showerror, err)))"))
        end
    else
        throw(ArgumentError("`update` is `:none`, `:all` or `:extensions`, not `$(update)`"))
    end
    init_workspace(deploy)
    write(deployment_path(deploy, "serve.jl"), serve_script(collect(keys(extensions))))
    launcher = deployment_path(deploy, "launch.sh")
    write(launcher, launch_script())
    chmod(launcher, 0o755)
    Pkg.precompile()
    # Last, so a record says the install finished.
    open(io -> TOML.print(io, deployment_record(file, clone_commit(deploy)); sorted = true), deployment_path(deploy, "record.toml"), "w")
    return deploy
end

"""
    serve_deployment(deploy, modules)

Serve an installed deployment with the extensions `serve.jl` loaded: the settings are read from
`dashiboard.toml` now, and the launch is refused when what install resolved no longer matches it.
"""
function serve_deployment(deploy::AbstractString, modules::AbstractVector{Module})
    file = read_workspace_file(deploy)
    record = TOML.parsefile(deployment_path(deploy, "record.toml"))
    problems = record_mismatches(record, file, clone_commit(deploy))
    isempty(problems) || error(join(problems, "\n"))
    (; dirs, fell_back) = resolve_pointers(deploy, file, Dict{String, Any}())
    missing_dirs = missing_directories(dirs)
    isempty(missing_dirs) || error(
        "no such directory: " * join(("the $(kind) directory `$(path)`" for (kind, path) in missing_dirs), ", ")
    )
    isempty(fell_back) ||
        @warn "no directory for some kinds of file: they are read from the deployment itself" kinds = fell_back
    (; host, port) = server_defaults(file)
    return launch(
        deploy;
        host = something(host, "127.0.0.1"), port = something(port, 8080),
        data_dir = dirs[:data], pipeline_dir = dirs[:pipeline], filter_dir = dirs[:filter],
        model_dir = dirs[:model], training_dir = dirs[:training],
        parser = Pipelines.default_parser(; plugins = [getfield(mod, :DEFAULT_PARSER) for mod in modules]),
        extensions = extension_sources(file), extension_of = provenance(modules),
    )
end
