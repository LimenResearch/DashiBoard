"""
    summarize(io::IO, model::Model, training::Training, data::AbstractData)

Display summary information concerning model (structure and number of parameters)
and data (number of batches and size of each batch).
"""
function summarize(io::IO, model::Model, training::Training, data::AbstractData{N}) where {N}
    templates = get_templates(data)
    m = model(templates)

    nsamples = ntuple(Fix1(get_nsamples, data), N)
    lens = cld.(nsamples, training.batchsize)
    sz = map(tplt -> (size(tplt)..., training.batchsize), templates)

    show(io, MIME"text/plain"(), m)

    print(io, "\n\n")

    if N === 1
        println(io, "Running with ", only(lens), " batches")
    elseif N === 2
        println(io, "Running with ", lens[1], " training batches and ", lens[2], " validation batches")
    end
    println(io, "Each batch has size $sz")

    return
end

function summarize(model::Model, training::Training, data::AbstractData)
    return sprint(summarize, model, training, data)
end
