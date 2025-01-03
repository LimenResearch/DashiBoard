function _validate(result::Result, data::AbstractData{1}, data_stream, streaming::Streaming)

    device_m = loadmodel(result, data, streaming.device)
    model = Model(result)
    loss, metrics = model.loss, Tuple(model.metrics)
    valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
    stats = (collect(Float64, valid_stats),)
    uuid = uuid4()

    return Result(; model, result.prefix, uuid, stats, iteration = 0, trained = false)
end

"""
    validate(result::Result, data::AbstractData{1}, streaming::Streaming)

Load model encoded in `result` and validate it on `data`.
"""
function validate(result::Result, data::AbstractData{1}, streaming::Streaming)
    return stream(data, streaming) do data_stream
        return _validate(result, data, data_stream, streaming)
    end
end
