# architecture helpers

function get_architecture(metadata::AbstractDict)
    name, components = metadata["name"], metadata["components"]
    return PARSER[].models[name](components)
end

function get_layer(layer_metadata::AbstractDict)
    params = make(SymbolDict, layer_metadata)
    name = pop!(params, :name)
    return PARSER[].layers[name](; params...)
end

# constructor helpers

function architecture(::Type{T}, architecture_metadata::AbstractDict) where {T}
    modules = map(fieldnames(T)) do k
        configs = get_configs(architecture_metadata, string(k))
        if isempty(configs)
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

get_context(metadata::AbstractDict) = make(SymbolDict, get_config(metadata, "options"))

const MODEL_CONTEXT = ScopedValue{SymbolDict}()
