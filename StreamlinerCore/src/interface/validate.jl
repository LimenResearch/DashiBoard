function _validate(
        model::Model, training::Training, data::AbstractData{1}, entry::BSON,
        data_stream; registry::Registry{P}
    ) where {P}
    device_m = loadmodel(model, training, get_templates(data), entry; registry)
    loss, metrics = model.loss, Tuple(model.metrics)
    valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
    stats = Dict("validation" => collect(Float64, valid_stats))
    result = StringDict("stats" => stats)

    return insert_entry(registry, result, model, training, data, entry; trained = false)
end

# TODO: allow custom settings for `device` and `batchsize`, without using `Training`?
"""
    validate(parser::Parser, data::AbstractData{1}, entry::BSON; registry::Registry)

Load model encoded in `entry` via `parser` and validate it on `data`.
"""
function validate(parser::Parser, data::AbstractData{1}, entry::BSON; registry::Registry)
    model = Model(parser, entry["model"])
    training = Training(parser, entry["training"])
    return stream(data; training.batchsize, training.device) do data_stream
        return _validate(model, training, data, entry, data_stream; registry)
    end
end
