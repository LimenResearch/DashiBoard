struct Architecture{F, M}
    name::Symbol
    forward::F
    modules::M
end

@layer :ignore Architecture trainable = (modules,)

(a::Architecture)(x) = a.forward(a.modules, x)

modules(a::Architecture) = a.modules

function Base.show(io::IO, ::MIME"text/plain", a::Architecture)
    print(io, "$(a.name) architecture with the following modules:")
    for (k, v) in pairs(modules(a))
        print(io, "\n")
        print(io, k, " => ")
        show(io, MIME"text/plain"(), v)
    end
    return
end

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

function parse_module(components::AbstractDict, k)
    configs = get(components, string(k), nothing)
    if isnothing(configs)
        msg = "Please provide layers for component '$k'."
        throw(ArgumentError(msg))
    end
    return map(parse_layer, configs)
end

parse_modules(components::AbstractDict, ks) = map(Fix1(parse_module, components), ks)

# additional context

parse_context(metadata::AbstractDict) = make(SymbolDict, get_config(metadata, "options"))

const MODEL_CONTEXT = ScopedValue{SymbolDict}()
