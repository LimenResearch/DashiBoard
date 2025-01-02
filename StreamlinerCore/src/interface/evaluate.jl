function _evaluate(device_m, data::AbstractData{1}, data_stream, select)
    eval_stream = Iterators.map(device_m, data_stream)
    return ingest(data, eval_stream, select)
end

"""
    evaluate(device_m, training::Training, data::AbstractData{1}, select::SymbolTuple = (:prediction,))

Evaluate model `device_m` on `data` using device and batchsize from `training`.
"""
function evaluate(device_m, training::Training, data::AbstractData{1}, select::SymbolTuple = (:prediction,))
    return stream(data; training.batchsize, training.device) do data_stream
        return _evaluate(device_m, data, data_stream, select)
    end
end

"""
    evaluate(
        model::Model, training::Training, data::AbstractData{1}, result::Result,
        select::SymbolTuple = (:prediction,)
    )

Load model encoded in `result` and evaluate it on `data`.
"""
function evaluate(
        model::Model, training::Training, data::AbstractData{1}, result::Result,
        select::SymbolTuple = (:prediction,)
    )
    device_m = loadmodel(model, training, data, result)
    return evaluate(device_m, training, data, select)
end
