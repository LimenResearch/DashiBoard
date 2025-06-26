@kwdef struct Settings
    parser::Pipelines.Parser
    model_directory::String
    training_directory::String
    data_directory::String
end

function with_settings(f, s::Settings, args...)
    return @with(
        Pipelines.PARSER => s.parser,
        Pipelines.MODEL_DIR => s.model_directory,
        Pipelines.TRAINING_DIR => s.training_directory,
        DataIngestion.DATA_DIR => s.data_directory,
        f(args...)
    )
end

struct ScopedHandler{F}
    handler::F
    settings::Settings
end

ScopedHandler(handler::F; kwargs...) where {F} = ScopedHandler(handler, Settings(; kwargs...))

(sh::ScopedHandler)(stream::HTTP.Stream) = with_settings(sh.handler, sh.settings, stream)
