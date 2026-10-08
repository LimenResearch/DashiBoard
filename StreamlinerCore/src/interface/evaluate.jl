"""
    evaluate(
            device_m, data::AbstractData{1}, streaming::Streaming,
            select::AbstractVector{Symbol} = [:prediction]
        )

Evaluate model `device_m` on `data` using streaming settings `streaming`.
`select` names the fields of the model's output to write, `[:prediction]` by default.
"""
function evaluate(
        device_m, data::AbstractData{1}, streaming::Streaming,
        select::AbstractVector{Symbol} = [:prediction];
        options...
    )

    return stream(data, streaming) do data_stream
        eval_stream = Iterators.map(device_m, data_stream)
        return ingest(data, eval_stream, select; options...)
    end
end

"""
    evaluate(
        dirname::AbstractString,
        model::Model, data::AbstractData{1}, streaming::Streaming,
        select::AbstractVector{Symbol} = [:prediction]
    )

Load `model` with weights saved in `dirname` and evaluate it on `data`
using streaming settings `streaming`.
`select` names the fields of the model's output to write, `[:prediction]` by default.
"""
function evaluate(
        dirname::AbstractString,
        model::Model, data::AbstractData{1}, streaming::Streaming,
        select::AbstractVector{Symbol} = [:prediction];
        options...
    )
    device_m = loadmodel(dirname, model, data, streaming.device)
    return evaluate(device_m, data, streaming, select; options...)
end
