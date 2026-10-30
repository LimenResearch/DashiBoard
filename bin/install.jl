# Install a DashiBoard deployment, or update one.
#
#     julia install.jl <deploy>                      install
#     julia install.jl <deploy> --update all         DashiBoard at the toml's current `rev`, everything re-resolved
#     julia install.jl <deploy> --update extensions  only the extensions move
#
# Copied alone to the client's machine, so it uses the standard library and `git` only. It clones
# the DashiBoard that `<deploy>/dashiboard.toml` pins, resolves it in a depot private to the
# deployment, and hands the rest to that release's own code, so an installer of any version
# installs any release the way that release expects.
module Install

using TOML: TOML

const OWN = ".dashiboard"

record_path(deploy) = joinpath(deploy, OWN, "record.toml")

"""
    starter_project(clone) -> Dict

The DashiBoard part of the deployment's `Project.toml`: DashiBoard and every package its own
`[sources]` names, each taken from its folder in `clone`. Read from the clone, so the list follows
the release.
"""
function starter_project(clone::AbstractString)
    root = joinpath(clone, "DashiBoard")
    sources = TOML.parsefile(joinpath(root, "Project.toml"))["sources"]
    paths = Dict("DashiBoard" => normpath(root))
    for (name, source) in sources
        paths[name] = normpath(joinpath(root, source["path"]))
    end
    uuid(path) = TOML.parsefile(joinpath(path, "Project.toml"))["uuid"]
    return Dict{String, Any}(
        "deps" => Dict(name => uuid(path) for (name, path) in paths),
        "sources" => Dict(name => Dict("path" => path) for (name, path) in paths),
    )
end

# A git command whose failure is reported with what git said.
function git(args::Cmd)
    err = IOBuffer()
    ok = success(pipeline(`git $args`; stdout = devnull, stderr = err))
    ok || error(strip(String(take!(err))))
    return nothing
end

# A url or rev git would read as an option is refused before git sees it.
function check_source(url::AbstractString, rev::AbstractString)
    (startswith(url, "-") || startswith(rev, "-")) && error("`[dashiboard]` url and rev may not start with `-`")
    return nothing
end

"""
    clone_at(url, rev, dest) -> commit

`url` cloned into `dest` and checked out at `rev`, a tag or a commit. A clone that git could not
finish is removed; a finished one is kept when the checkout fails, so fixing `rev` and running
again moves it rather than downloading it again.
"""
function clone_at(url::AbstractString, rev::AbstractString, dest::AbstractString)
    failed(e) = error("could not check out `$(rev)` of `$(url)`: $(sprint(showerror, e))")
    try
        git(`clone --quiet -- $url $dest`)
    catch e
        rm(dest; recursive = true, force = true)
        failed(e)
    end
    try
        git(`-C $dest checkout --quiet --detach $rev`)
    catch e
        failed(e)
    end
    return readchomp(`git -C $dest rev-parse HEAD`)
end

"""
    checkout_update(clone, url, rev) -> commit

`clone` moved to `rev` of `url` — the toml's url now, which a full update follows even when it is
not the one the clone was made from.
"""
function checkout_update(clone::AbstractString, url::AbstractString, rev::AbstractString)
    git(`-C $clone remote set-url origin $url`)
    git(`-C $clone fetch --quiet --tags origin`)
    git(`-C $clone checkout --quiet --detach $rev`)
    return readchomp(`git -C $clone rev-parse HEAD`)
end

"""
    prepare_clone(clone, url, rev) -> commit

The clone at `rev` of `url`: made when there is none, moved when an earlier run left one.
"""
function prepare_clone(clone::AbstractString, url::AbstractString, rev::AbstractString)
    check_source(url, rev)
    return isdir(clone) ? checkout_update(clone, url, rev) : clone_at(url, rev, clone)
end

const KEPT = ("Project.toml", "Manifest.toml", "serve.jl", "launch.sh", "record.toml")

"""
    with_rollback(f, deploy)

Run an update, and put the deployment back as it was if it fails: its files and the clone's
commit, so a client's working server is not left half-updated.
"""
function with_rollback(f, deploy::AbstractString)
    own = joinpath(deploy, OWN)
    clone = joinpath(own, "DashiBoard")
    saved = Dict(name => read(joinpath(own, name)) for name in KEPT if isfile(joinpath(own, name)))
    commit = readchomp(`git -C $clone rev-parse HEAD`)
    try
        return f()
    catch
        for name in KEPT
            path = joinpath(own, name)
            haskey(saved, name) ? write(path, saved[name]) : rm(path; force = true)
        end
        git(`-C $clone checkout --quiet --detach $commit`)
        rethrow()
    end
end

"""
    check_not_installed(deploy)

Refuse to install over an installed deployment: changing one is an update, said on purpose.
"""
function check_not_installed(deploy::AbstractString)
    isfile(record_path(deploy)) && error(
        "`$(deploy)` is installed already: run `install.jl $(deploy) --update all` or `--update extensions`"
    )
    return nothing
end

function dashiboard_source(deploy)
    file = TOML.parsefile(joinpath(deploy, "dashiboard.toml"))
    source = get(file, "dashiboard", nothing)
    ok = source isa AbstractDict && get(source, "url", nothing) isa String && get(source, "rev", nothing) isa String
    ok || error("`$(joinpath(deploy, "dashiboard.toml"))` needs a `[dashiboard]` table with a `url` and a `rev`")
    return source["url"], source["rev"]
end

# Julia in the deployment's project and private depot, with nothing inherited that would point it
# elsewhere.
function julia(deploy, args::Cmd)
    own = joinpath(deploy, OWN)
    vars = Dict{String, String}(k => v for (k, v) in ENV if !(k in ("JULIA_LOAD_PATH", "JULIA_PROJECT", "JULIA_DEPOT_PATH")))
    vars["JULIA_DEPOT_PATH"] = joinpath(own, "depot")
    return setenv(`$(Base.julia_cmd()) --startup-file=no --project=$own $args`, vars)
end

function main(args)
    length(args) in (1, 3) && (length(args) == 1 || args[2] == "--update") ||
        error("usage: install.jl <deploy> [--update all|extensions]")
    deploy = normpath(abspath(args[1]))
    mode = length(args) == 1 ? "none" : args[3]
    mode in ("none", "all", "extensions") || error("`--update` takes `all` or `extensions`")
    url, rev = dashiboard_source(deploy)
    own = joinpath(deploy, OWN)
    clone = joinpath(own, "DashiBoard")
    if mode == "none"
        check_not_installed(deploy)
    else
        isfile(record_path(deploy)) || error("`$(deploy)` is not installed: run `install.jl $(deploy)`")
    end
    steps = function ()
        if mode != "extensions"
            mkpath(own)
            prepare_clone(clone, url, rev)
        end
        if mode != "extensions"
            # Afresh: what was resolved before does not constrain a full update.
            open(io -> TOML.print(io, starter_project(clone); sorted = true), joinpath(own, "Project.toml"), "w")
            rm(joinpath(own, "Manifest.toml"); force = true)
            # A fresh depot holds no registry, and resolving does not fetch one; a full update
            # resolves against the registry as it is today.
            run(julia(deploy, `-e 'using Pkg; isempty(Pkg.Registry.reachable_registries()) && Pkg.Registry.add("General"); Pkg.Registry.update(); Pkg.resolve(); Pkg.instantiate()'`))
        end
        run(julia(deploy, `-e 'using DashiBoard; DashiBoard.install_deployment(ARGS[1]; update = Symbol(ARGS[2]))' $deploy $mode`))
    end
    # A first install that fails keeps what it downloaded, and no record, so nothing launches it;
    # running install again resumes. An update that fails restores the deployment it found.
    mode == "none" ? steps() : with_rollback(steps, deploy)
    return 0
end

end # module Install

# Run as a script; included, as the tests do, it only defines the module. What went wrong is said
# as a sentence: a step that failed has already printed its own output.
if abspath(PROGRAM_FILE) == @__FILE__()
    try
        exit(Install.main(ARGS))
    catch e
        e isa InterruptException && rethrow()
        println(stderr, "ERROR: ", e isa ProcessFailedException ? "a step failed; its output is above" : sprint(showerror, e))
        exit(1)
    end
end
