"""
    loadmodel(model::Model, data::AbstractData, device)

Load model encoded in `model` on the `device`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.
"""
loadmodel(model::Model, data::AbstractData, device) = device(model(data))

"""
    loadmodel(result::Result, data::AbstractData, device)

Load model encoded in `result` on the `device`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.

!!! warning
    It is recommended to call [`has_weights`](@ref) beforehand.
    Only call `loadmodel` if `has_weights(result)` returns `true`.
"""
function loadmodel(result::Result, data::AbstractData, device)

    result.trained || throw(ArgumentError("Model was not trained"))
    result.successful || throw(ArgumentError("Unsuccessful result, no weights were saved"))

    m = Model(result)(data)
    path = get_path(result)

    jldopen(maybe_buffer(path)) do file
        state = file["model_state"]
        loadmodel!(m, state)
    end

    return device(m)
end

# For local file system, read from path
maybe_buffer(path::AbstractString) = path

# For remote file systems (e.g., S3 paths), load in memory
maybe_buffer(path) = IOBuffer(read(path))
