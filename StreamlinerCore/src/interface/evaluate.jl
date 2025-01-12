"""
    evaluate(
            device_m, data::AbstractData{1}, streaming::Streaming,
            select::SymbolTuple = (:prediction,)
        )

Evaluate model `device_m` on `data` using streaming settings `streaming`.
"""
function evaluate(
        device_m, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )

    return stream(data, streaming) do data_stream
        eval_stream = Iterators.map(device_m, data_stream)
        return ingest(data, eval_stream, select)
    end
end

"""
    evaluate(
        path::AbstractString,
        model::Model, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )

Load `model` with weights saved in `path` and evaluate it on `data`
using streaming settings `streaming`.
"""
function evaluate(
        path::AbstractString,
        model::Model, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )
    device_m = loadmodel(path, model, data, streaming.device)
    return evaluate(device_m, data, streaming, select)
end
