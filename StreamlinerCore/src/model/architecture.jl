# architecture helpers

function get_architecture(config::AbstractDict)
    name, components = config[:name], config[:components]
    return PARSER[].models[name](components)
end

function get_layer(config::AbstractDict)
    params, name = pop(config, :name)
    return PARSER[].layers[name](; params...)
end

# constructor helpers

function architecture(::Type{T}, config::AbstractDict) where {T}
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

get_context(config::AbstractDict) = get_config(config, :options)

const MODEL_CONTEXT = ScopedValue{SymbolDict}()
