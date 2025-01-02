"""
    loadmodel(model::Model, training::Training, data::AbstractData, result::Result)

Load model encoded in `result`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.

!!! warning
    It is recommended to call [`has_weights`](@ref) beforehand.
    Only call `loadmodel` if `has_weights(result)` returns `true`.
"""
function loadmodel(model::Model, training::Training, data::AbstractData, result::Result)

    has_weights(result) || throw(ArgumentError("Unsuccessful result, no weights were saved"))
    
    m = model(data)
    path = get_path(result)
    loadmodel!(m, read_state(path)["model_state"])

    device = training.device
    return device(m)
end
