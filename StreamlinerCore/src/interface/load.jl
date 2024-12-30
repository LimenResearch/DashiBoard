function loadmodel(
        model::Model, training::Training, templates::Tup, entry::BSON;
        registry::Registry{P}
    ) where {P}

    device = training.device
    m = model(templates)

    result = entry["result"]
    path = joinpath(P(result["prefix"]), result["path"])

    loadmodel!(m, read_state(path)["model_state"])

    return device(m)
end

"""
    loadmodel(parser::Parser, templates::Tup, entry::BSON; registry::Registry)

Load model encoded in `entry` via `parser`.
The `templates` are required as the model can only be initialized once the data
dimensions are known.

!!! warning
    It is recommended to call [`has_weights`](@ref) beforehand.
    Only call `loadmodel` if `has_weights(entry)` returns `true`.
"""
function loadmodel(parser::Parser, templates::Tup, entry::BSON; registry::Registry)
    model = Model(parser, entry["model"])
    training = Training(parser, entry["training"])
    return loadmodel(model, training, templates, entry; registry)
end
