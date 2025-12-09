# architecture helpers

function parse_architecture(metadata::AbstractDict)
    name, components = metadata["name"], metadata["components"]
    return PARSER[].models[name](components)
end

function parse_layer(layer_metadata::AbstractDict)
    params = make(SymbolDict, layer_metadata)
    name = pop!(params, :name)
    return PARSER[].layers[name](; params...)
end

# constructor helpers

function architecture(::Type{T}, architecture_metadata::AbstractDict) where {T}
    modules = map(fieldnames(T)) do k
        configs = get(architecture_metadata, string(k), nothing)
        if isnothing(configs)
            msg = "Please provide layers for component '$k'."
            throw(ArgumentError(msg))
        end
        return map(parse_layer, configs)
    end
    return T(modules...)
end

# additional context

parse_context(metadata::AbstractDict) = make(SymbolDict, get_config(metadata, "options"))

const MODEL_CONTEXT = ScopedValue{SymbolDict}()
