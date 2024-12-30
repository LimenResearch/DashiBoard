function _validate(
        model::Model, training::Training, data::AbstractData{1}, entry::Entry{P},
        data_stream
    ) where {P}

    device_m = loadmodel(model, training, get_templates(data), entry)
    loss, metrics = model.loss, Tuple(model.metrics)
    valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
    stats = Dict("validation" => collect(Float64, valid_stats))
    (; prefix, filename) = entry.result
    result = EntryResult{P}(; prefix, filename, stats, iteration = 0)
    return generate_entry(result, model, training, data, entry; trained = false)
end

# TODO: allow custom settings for `device` and `batchsize`, without using `Training`?
"""
    validate(parser::Parser, data::AbstractData{1}, entry::Entry)

Load model encoded in `entry` via `parser` and validate it on `data`.
"""
function validate(parser::Parser, data::AbstractData{1}, entry::Entry)
    model = Model(parser, entry.key.model)
    training = Training(parser, entry.key.training)
    return stream(data; training.batchsize, training.device) do data_stream
        return _validate(model, training, data, entry, data_stream)
    end
end
