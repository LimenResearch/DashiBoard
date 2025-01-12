"""
    loadmodel(model::Model, data::AbstractData, device)

Load model encoded in `model` on the `device`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.
"""
loadmodel(model::Model, data::AbstractData, device) = device(model(data))

function loadmodel(::Nothing, model::Model, data::AbstractData, device)
    return loadmodel(model, data, device)
end

"""
    loadmodel(path::AbstractString, model::Model, data::AbstractData, device)

Load model encoded in `result` on the `device`.
The object `data` is required as the model can only be initialized once the data
dimensions are known.
"""
function loadmodel(path::AbstractString, model::Model, data::AbstractData, device)

    m = model(data)

    jldopen(path) do file
        state = file["model_state"]
        loadmodel!(m, state)
    end

    return device(m)
end
