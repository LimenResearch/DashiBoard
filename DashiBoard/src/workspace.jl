# A workspace: the directory the server is launched against, where each kind of file is, and the
# extensions it names.
#
# The layout is the default answer to the directories Pipelines' `@with` block already takes —
# `MODEL_DIR`, `TRAINING_DIR` — and DataIngestion's `DATA_DIR`; nothing here replaces them. A
# `dashiboard.toml` at the root can say otherwise. In that order: the file, the conventional
# folder when it exists, the root.

const WORKSPACE_FILE = "dashiboard.toml"

@kwarg struct ServerConfig
    host::String = "127.0.0.1"
    port::Int = 8080
end

@kwarg struct DirectoriesConfig
    data::String = "data"
    pipeline::String = "pipeline"
    filter::String = "filter"
    model::String = "model"
    training::String = "training"
end

@kwarg struct WorkspaceConfig
    extensions::Dict{String, ExtensionConfig} = Dict{String, ExtensionConfig}()
    directories::DirectoriesConfig = DirectoriesConfig()
    server::ServerConfig = ServerConfig()
end

# What a workspace file may say, checked before any of it is used: a table DashiBoard does not
# know, or a value of the wrong kind, would otherwise be skipped or fail somewhere unrelated.
# TODO: error on additional properties?
WorkspaceConfig(file::AbstractDict) = StructUtils.make(WorkspaceConfig, file)

"""
    read_workspace_file(workspace) -> WorkspaceConfig

The parsed `dashiboard.toml` at the root of `workspace`, or an empty `Dict` when there is none.
A file that says something DashiBoard does not read — a misspelt table, a value of the wrong
kind — is refused, naming the entry.
"""
function read_workspace_file(workspace::AbstractString)::WorkspaceConfig
    path = joinpath(workspace, WORKSPACE_FILE)
    return isfile(path) ? WorkspaceConfig(TOML.parsefile(path)) : WorkspaceConfig()
end

"""
    init_workspace(dir)

Initialize folder structure. Error if the folder has anything other than a `quarantine` subfolder.

A table goes to the data folder, a cards document to the pipeline folder, a filters document to
the filter folder, a model configuration to the model folder, a training one to the training
folder. The folders are the ones the workspace file names under `[directories]` when there is
one, and `data`, `pipeline`, `filter`, `model`, `training` otherwise.
"""
function init_workspace(dir::AbstractString, config::WorkspaceConfig = read_workspace_file(dir))
    # Where each kind goes: the folder the workspace file names, as written, else the kind's own.
    for kind in propertynames(config.directories)
        dir = getproperty(config.directories, kind)
        mkpath(abspath(root, dir))
    end
    return
end

# Extensions: what each contributed.

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

function get_handlers(m::Module, workspace::AbstractString, config::WorkspaceConfig = read_workspace_file(workspace))
    (; directories, extensions) = config

    data_dir::AbstractString = abspath(workspace, directories.data)
    pipeline_dir::AbstractString = abspath(workspace, directories.pipeline)
    filter_dir::AbstractString = abspath(workspace, directories.filter)
    model_dir::AbstractString = abspath(workspace, directories.model)
    training_dir::AbstractString = abspath(workspace, directories.training)

    plugin_modules = Module[getglobal(m, Symbol(ext)) for (ext, cfg) in pairs(extensions) if cfg.is_plugin]
    plugins = Parser[plugin_module.DEFAULT_PARSER for plugin_module in plugin_modules]
    parser = default_parser(; plugins)
    extension_of = provenance(plugin_modules)

    return get_handlers(
        abspath(workspace);
        data_dir, pipeline_dir, filter_dir, model_dir, training_dir,
        parser, extensions, extension_of
    )
end

function launch(
        m::Module, workspace::AbstractString, config::WorkspaceConfig = read_workspace_file(workspace);
        async::Bool = false
    )

    handlers, stream_handlers, probe_handlers = get_handlers(m, workspace, config)
    (; host, port) = config.server
    return launch(handlers, stream_handlers, probe_handlers; host, port, async)
end
