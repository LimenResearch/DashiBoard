function _evaluate(device_m, data::AbstractData{1}, data_stream, select)
    eval_stream = Iterators.map(device_m, data_stream)
    return ingest(data, eval_stream, select)
end

"""
    evaluate(
            device_m, data::AbstractData{1}, streaming::Streaming,
            select::SymbolTuple = (:prediction,)
        )

Evaluate model `device_m` on `data` using streaming options `streaming`.
"""
function evaluate(
        device_m, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )

    return stream(data, streaming) do data_stream
        return _evaluate(device_m, data, data_stream, select)
    end
end

"""
    evaluate(
        result::Result, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )

Load model encoded in `result` and evaluate it on `data`.
"""
function evaluate(
        result::Result, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )
    device_m = loadmodel(result, data, streaming.device)
    return evaluate(device_m, data, streaming, select)
end
