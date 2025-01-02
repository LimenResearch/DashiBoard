function _validate(
        model::Model, training::Training, data::AbstractData{1}, result::Result{P},
        data_stream
    ) where {P}

    device_m = loadmodel(model, training, data, result)
    loss, metrics = model.loss, Tuple(model.metrics)
    valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
    stats = (collect(Float64, valid_stats),)

    (; prefix, uuid) = result
    return Result{P, 1}(; prefix, uuid, has_weights = false, stats, iteration = 0)
end

# TODO: allow custom settings for `device` and `batchsize`, without using `Training`?
"""
    validate(model::Model, training::Training, data::AbstractData{1}, result::Result)

Load model encoded in `result` and validate it on `data`.
"""
function validate(model::Model, training::Training, data::AbstractData{1}, result::Result)
    return stream(data; training.batchsize, training.device) do data_stream
        return _validate(model, training, data, result, data_stream)
    end
end
