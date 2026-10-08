# Launch DashiBoard against a workspace.
#
#   julia --project=DashiBoard bin/launch.jl <workspace> [flags]
#
# The workspace is a directory laid out as `data/ pipeline/ filter/ model/ training/`, or a plain
# folder, or anything in between: each directory is taken from a flag, else from `[directories]`
# in the workspace's `dashiboard.toml`, else from the conventional folder when it exists, else
# from the workspace itself. `--init` sorts a plain folder into the layout and exits.
#
# With extensions (`[extensions]` in the file, or `--extensions`) the launch has two stages. The
# first, this process, reads the workspace and builds one environment holding the server's
# packages and the extensions, resolved together. The second is the same script run again
# *inside* that environment: it loads everything from there and serves. So what is loaded is
# what was resolved, where loading the server first and the extensions after would run them
# against versions they were not resolved with. Without extensions there is one stage.
#
# The second stage is handed what the first one worked out — the directories, the address, the
# sources — rather than the command line again: a relative path means what it meant where the
# command was typed, and that environment holds the server's packages, not the launcher's.
using TOML: TOML

# The server's package, found without loading it: the first stage needs only the part that
# reads a workspace, which stands on the standard library.
const PACKAGE = let path = Base.find_package("DashiBoard")
    isnothing(path) && error("DashiBoard is not in this environment; run with `--project=DashiBoard`")
    dirname(dirname(path))
end
include(joinpath(PACKAGE, "src", "Workspace.jl"))
using .Workspace: Workspace

# The command line. `ArgParse` is loaded here, by the stage that reads a command line.
function arguments(ARGS)
    ArgParse = Base.require(Main, :ArgParse)
    return Base.invokelatest() do
        s = ArgParse.ArgParseSettings()
        option(name, help, type) = ArgParse.add_arg_table!(s, name, Dict(:help => help, :arg_type => type))
        option("--host", "address to bind (default: the workspace file's, else 127.0.0.1)", String)
        option("--port", "port to bind (default: the workspace file's, else 8080)", Int)
        option("--data_dir", "directory of the tables", String)
        option("--pipeline_dir", "directory of the pipeline documents", String)
        option("--filter_dir", "directory of the filters documents", String)
        option("--model_dir", "directory of the model configurations", String)
        option("--training_dir", "directory of the training configurations", String)
        option("--extensions", "extensions to register, `Name=path` or `Name=url@rev`, comma-separated; replaces the workspace file's", String)
        ArgParse.add_arg_table!(s, "--init", Dict(:help => "sort the workspace's loose files into the layout and exit", :action => :store_true))
        ArgParse.add_arg_table!(s, "workspace", Dict(:help => "the directory to serve", :required => true))
        ArgParse.parse_args(ARGS, s)
    end
end

# What the first stage hands the second, in the environment variable of this name.
const HANDOVER = "DASHIBOARD_LAUNCH"

# The second stage: this script again, in the environment built for the extensions, speaking
# through this process's own terminal. The child is stopped when this process is, so stopping the
# launcher stops the server.
function relaunch(env, launch)
    # The server loads from its own environment and nowhere this process was told to look: a
    # load path or a project set for the launcher — by a test runner, say — is not handed on.
    inherited = filter(((name, _),) -> !(name in ("JULIA_LOAD_PATH", "JULIA_PROJECT")), collect(ENV))
    variables = Dict{String, String}(inherited)
    variables[HANDOVER] = sprint(TOML.print, launch)
    command = setenv(`$(Base.julia_cmd()) --project=$(env) $(@__FILE__)`, variables)
    child = run(pipeline(command; stdin, stdout, stderr); wait = false)
    atexit(() -> process_running(child) && kill(child))
    wait(child)
    return success(child) ? 0 : max(child.exitcode, 1)
end

fallback_warning(kinds) = isempty(kinds) ||
    @warn "no directory for some kinds of file: they are read from the workspace itself; `--init` lays the folder out" kinds

# Load the server and what the workspace names, and serve. Each step is called in the world the
# step before it left: the server's functions exist only once it is loaded, and it has to see
# the methods an extension defines — how its funnel describes itself, say — once those are.
function serve(workspace, dirs, host, port, sources)
    DashiBoard = Base.require(Main, :DashiBoard)
    modules = Base.invokelatest(DashiBoard.load_extensions, sources)
    return Base.invokelatest() do
        DashiBoard.launch(
            workspace;
            host, port,
            data_dir = dirs[:data], pipeline_dir = dirs[:pipeline], filter_dir = dirs[:filter],
            model_dir = dirs[:model], training_dir = dirs[:training],
            parser = DashiBoard.Pipelines.default_parser(; plugins = [getfield(mod, :DEFAULT_PARSER) for mod in modules]),
            extensions = sources, extension_of = DashiBoard.provenance(modules),
        )
    end
end

function (@main)(ARGS)
    # The second stage: everything is already worked out.
    if haskey(ENV, HANDOVER)
        launch = TOML.parse(ENV[HANDOVER])
        fallback_warning(Symbol.(launch["fell_back"]))
        dirs = Dict(Symbol(kind) => dir for (kind, dir) in launch["dirs"])
        return serve(launch["workspace"], dirs, launch["host"], launch["port"], launch["sources"])
    end

    d = arguments(ARGS)
    workspace = d["workspace"]
    # A folder that is not there is a mistake in the command, not an empty workspace to serve.
    isdir(workspace) || error("the workspace `$(workspace)` does not exist")

    if d["init"]
        DashiBoard = Base.require(Main, :DashiBoard)
        Base.invokelatest(DashiBoard.init_workspace, workspace)
        return 0
    end

    file = Workspace.read_workspace_file(workspace)
    flags = Dict{String, Any}(k => v for (k, v) in d if !isnothing(v))
    (; dirs, fell_back) = Workspace.resolve_pointers(workspace, file, flags)
    missing_dirs = Workspace.missing_directories(dirs)
    isempty(missing_dirs) || error(
        "no such directory: " * join(("the $(kind) directory `$(path)`" for (kind, path) in missing_dirs), ", ")
    )
    defaults = Workspace.server_defaults(file)
    host = something(d["host"], defaults.host, "127.0.0.1")
    port = something(d["port"], defaults.port, 8080)
    sources = Workspace.locate_sources(workspace, Workspace.extension_sources(file, flags))

    if !isempty(sources)
        env = Workspace.extension_environment(workspace, sources)
        return relaunch(
            env, Dict(
                "workspace" => abspath(workspace), "host" => host, "port" => port, "sources" => sources,
                "dirs" => Dict(string(kind) => dir for (kind, dir) in dirs), "fell_back" => string.(fell_back),
            )
        )
    end

    fallback_warning(fell_back)
    return serve(workspace, dirs, host, port, sources)
end
