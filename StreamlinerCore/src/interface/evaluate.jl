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
        parser::Parser, data::AbstractData{1}, entry::BSON,
        select::SymbolTuple = (:prediction,); registry::Registry
    )

Load model encoded in `entry` via `parser` and evaluate it on `data`.
"""
function evaluate(
        parser::Parser, data::AbstractData{1}, entry::BSON,
        select::SymbolTuple = (:prediction,); registry::Registry
    )
    model = Model(parser, entry["model"])
    training = Training(parser, entry["training"])
    device_m = loadmodel(model, training, get_templates(data), entry; registry)
    return evaluate(device_m, training, data, select)
end
