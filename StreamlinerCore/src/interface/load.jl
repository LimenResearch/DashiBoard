function loadmodel(model::Model, training::Training, templates::Tup, entry::Entry)

    device = training.device
    m = model(templates)

    path = joinpath(entry.result.prefix, entry.result.filename)

    loadmodel!(m, read_state(path)["model_state"])

    return device(m)
end

"""
    loadmodel(parser::Parser, templates::Tup, entry::Entry)

Load model encoded in `entry` via `parser`.
The `templates` are required as the model can only be initialized once the data
dimensions are known.

!!! warning
    It is recommended to call [`has_weights`](@ref) beforehand.
    Only call `loadmodel` if `has_weights(entry)` returns `true`.
"""
function loadmodel(parser::Parser, templates::Tup, entry::Entry)
    model = Model(parser, entry.key.model)
    training = Training(parser, entry.key.training)
    return loadmodel(model, training, templates, entry)
end
