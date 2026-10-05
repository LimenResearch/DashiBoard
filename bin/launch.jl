# Launch DashiBoard against a workspace.
#
#   julia --project=DashiBoard bin/launch.jl <workspace> [flags]
#
# The workspace is a directory laid out as `data/ pipeline/ filter/ model/ training/`, or a plain
# folder, or anything in between: each directory is taken from a flag, else from `[directories]`
# in the workspace's `dashiboard.toml`, else from the conventional folder when it exists, else
# from the workspace itself. The extensions the file names (`[extensions]`, or `--extensions`)
# are resolved into an environment under the workspace and registered. `--init` sorts a plain
# folder into the layout and exits.
using ArgParse: ArgParseSettings, @add_arg_table!, parse_args
using DashiBoard: DashiBoard, launch
using Pipelines: Pipelines

function (@main)(ARGS)
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--host"
        help = "address to bind (default: the workspace file's, else 127.0.0.1)"
        arg_type = String
        "--port"
        help = "port to bind (default: the workspace file's, else 8080)"
        arg_type = Int
        "--data_dir"
        help = "directory of the tables"
        arg_type = String
        "--pipeline_dir"
        help = "directory of the pipeline documents"
        arg_type = String
        "--filter_dir"
        help = "directory of the filters documents"
        arg_type = String
        "--model_dir"
        help = "directory of the model configurations"
        arg_type = String
        "--training_dir"
        help = "directory of the training configurations"
        arg_type = String
        "--extensions"
        help = "extensions to register, `Name=path` or `Name=url@rev`, comma-separated; replaces the workspace file's"
        arg_type = String
        "--init"
        help = "sort the workspace's loose files into the layout and exit"
        action = :store_true
        "workspace"
        help = "the directory to serve"
        required = true
    end

    d = parse_args(ARGS, s)
    workspace = d["workspace"]
    # A folder that is not there is a mistake in the command, not an empty workspace to serve.
    isdir(workspace) || error("the workspace `$(workspace)` does not exist")

    if d["init"]
        DashiBoard.init_workspace(workspace)
        return 0
    end

    file = DashiBoard.read_workspace_file(workspace)
    flags = Dict{String, Any}(k => v for (k, v) in d if !isnothing(v))
    (; dirs, fell_back) = DashiBoard.resolve_pointers(workspace, file, flags)
    missing_dirs = DashiBoard.missing_directories(dirs)
    isempty(missing_dirs) || error(
        "no such directory: " * join(("the $(kind) directory `$(path)`" for (kind, path) in missing_dirs), ", ")
    )
    if !isempty(fell_back)
        @warn "no directory for some kinds of file: they are read from the workspace itself; `--init` lays the folder out" kinds = fell_back
    end
    defaults = DashiBoard.server_defaults(file)
    host = something(d["host"], defaults.host, "127.0.0.1")
    port = something(d["port"], defaults.port, 8080)

    sources = DashiBoard.locate_sources(workspace, DashiBoard.extension_sources(file, flags))
    extension_of = Dict{String, String}()
    plugins = Pipelines.SC.Parser[]
    if !isempty(sources)
        env = DashiBoard.extension_environment(workspace, sources)
        modules = DashiBoard.load_extensions(sources; env)
        extension_of = DashiBoard.provenance(modules)
        plugins = [getfield(mod, :DEFAULT_PARSER) for mod in modules]
    end

    # Called in the latest world: an extension loaded a moment ago defines methods — how its
    # funnel describes itself, say — that the server's handlers have to see.
    return Base.invokelatest(
        launch,
        workspace;
        host, port,
        data_dir = dirs[:data], pipeline_dir = dirs[:pipeline], filter_dir = dirs[:filter],
        model_dir = dirs[:model], training_dir = dirs[:training],
        parser = Pipelines.default_parser(; plugins),
        extensions = sources, extension_of,
    )
end
