# architecture helpers

function get_architecture(config::Config)
    (; name, components) = config
    return PARSER[].models[name](components)
end

function get_layer(config::Config)
    params = SymbolDict(config)
    name = pop!(params, :name)
    return PARSER[].layers[name](; params...)
end

# constructor helpers

function architecture(::Type{T}, config::Config) where {T}
    modules = map(fieldnames(T)) do k
        configs = get(config, k, nothing)
        if isnothing(configs) || isempty(configs)
            msg = """
            Empty chain of layers is not supported.
            Please provide at least one layer for component '$k'.
            """
            throw(ArgumentError(msg))
        end
        return map(get_layer, configs)
    end
    return T(modules...)
end

# additional context

get_context(config::Config) = SymbolDict(config.options)

const MODEL_CONTEXT = ScopedValue{SymbolDict}()
