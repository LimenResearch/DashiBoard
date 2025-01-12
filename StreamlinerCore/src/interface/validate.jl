"""
    validate(
        filename::AbstractString,
        model::Model,
        data::AbstractData{1},
        streaming::Streaming
    )

Load `model` with weights saved in `filename` and validate it on `data`
using streaming settings `streaming`.
"""
function validate(
        filename::AbstractString,
        model::Model,
        data::AbstractData{1},
        streaming::Streaming
    )

    return stream(data, streaming) do data_stream

        device_m = loadmodel(filename, model, data, streaming.device)
        loss, metrics = model.loss, Tuple(model.metrics)
        valid_stats = compute_metrics((loss, metrics...), device_m, data_stream)
        stats = (collect(Float64, valid_stats),)

        return Result(; stats, iteration = 0, trained = false)
    end
end
