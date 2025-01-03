"""
    loadmodel(model::Model, data::AbstractData, training::Training)

Load model encoded in `model`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.
"""
loadmodel(model::Model, data::AbstractData, training::Training) = training.device(model(data))

"""
    loadmodel(result::Union{Model, Result}, data::AbstractData, training::Training)

Load model encoded in `result`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.

!!! warning
    It is recommended to call [`has_weights`](@ref) beforehand.
    Only call `loadmodel` if `has_weights(result)` returns `true`.
"""
function loadmodel(result::Result, data::AbstractData, training::Training)

    result.trained || throw(ArgumentError("Model was not trained"))
    result.successful || throw(ArgumentError("Unsuccessful result, no weights were saved"))

    m = Model(result)(data)
    path = get_path(result)
    loadmodel!(m, read_state(path)["model_state"])

    device = training.device
    return device(m)
end
