"""
    evaluate(
            device_m, data::AbstractData{1}, streaming::Streaming,
            select::SymbolTuple = (:prediction,)
        )

Evaluate model `device_m` on `data` using streaming settings `streaming`.
"""
function evaluate(
        device_m, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,);
        options...
    )

    return stream(data, streaming) do data_stream
        eval_stream = Iterators.map(device_m, data_stream)
        return ingest(data, eval_stream, select; options...)
    end
end

"""
    evaluate(
        filename::AbstractString,
        model::Model, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,)
    )

Load `model` with weights saved in `filename` and evaluate it on `data`
using streaming settings `streaming`.
"""
function evaluate(
        filename::AbstractString,
        model::Model, data::AbstractData{1}, streaming::Streaming,
        select::SymbolTuple = (:prediction,);
        options...
    )
    device_m = loadmodel(filename, model, data, streaming.device)
    return evaluate(device_m, data, streaming, select; options...)
end
