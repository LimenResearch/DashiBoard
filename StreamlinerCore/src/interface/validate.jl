function _validate(result::Result, training::Training, data::AbstractData{1}, data_stream)

    device_m = loadmodel(result, training, data)
    model = Model(result)
    loss, metrics = model.loss, Tuple(model.metrics)
    valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
    stats = (collect(Float64, valid_stats),)
    uuid = uuid4()

    return Result(; model, result.prefix, uuid, stats, iteration = 0, trained = false)
end

# TODO: allow custom settings for `device` and `batchsize`, without using `Training`?
"""
    validate(result::Result, training::Training, data::AbstractData{1})

Load model encoded in `result` and validate it on `data`.
"""
function validate(result::Result, training::Training, data::AbstractData{1})
    return stream(data; training.batchsize, training.device) do data_stream
        return _validate(result, training, data, data_stream)
    end
end
