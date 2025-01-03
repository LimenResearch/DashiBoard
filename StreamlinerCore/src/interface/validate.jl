function _validate(result::Result, data::AbstractData{1}, data_stream, training::Training)

    device_m = loadmodel(result, data, training)
    model = Model(result)
    loss, metrics = model.loss, Tuple(model.metrics)
    valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
    stats = (collect(Float64, valid_stats),)
    uuid = uuid4()

    return Result(; model, result.prefix, uuid, stats, iteration = 0, trained = false)
end

# TODO: allow custom settings for `device` and `batchsize`, without using `Training`?
"""
    validate(result::Result, data::AbstractData{1}, training::Training)

Load model encoded in `result` and validate it on `data`.
"""
function validate(result::Result, data::AbstractData{1}, training::Training)
    return stream(data; training.batchsize, training.device) do data_stream
        return _validate(result, data, data_stream, training)
    end
end
