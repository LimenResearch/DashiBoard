# Entry management

@kwdef struct EntryKey
    model::StringDict
    training::StringDict
    data::StringDict
    from::Maybe{UUID}
    trained::Bool
    resumed::Maybe{Bool}
end

@kwdef struct EntryResult{P}
    prefix::P
    filename::Maybe{String}
    iteration::Int
    stats::Dict{String, Vector{Float64}}
end

@kwdef struct Entry{P}
    key::EntryKey
    result::EntryResult{P}
    summary::StringDict
    time::DateTime
    uuid::UUID
end

get_metadata(d::AbstractDict) = d

function to_key(
        model, training, data, entry::Maybe{Entry} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )

    return EntryKey(
        model = get_metadata(model),
        training = get_metadata(training),
        data = get_metadata(data),
        from = isnothing(entry) ? nothing : entry.uuid,
        trained = trained,
        resumed = resumed,
    )
end

function generate_entry(
        result::EntryResult, model::Model, training::Training, data::AbstractData,
        entry::Maybe{Entry} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )

    summary = get_summary(data)
    key = to_key(model, training, data, entry; trained, resumed)
    time = now()
    uuid = uuid4()

    return Entry(; key, result, summary, time, uuid)
end

"""
    has_weights(entry::Entry)

Return `true` if `entry` is a successful training entry, `false` otherwise
"""
has_weights(entry::Entry) = !isnothing(entry.result.filename)

# helpers to load weights

read_state(io::IO) = load(io)
# Fallback for non-standard paths, e.g., S3 paths
read_state(path) = read_state(IOBuffer(read(path)))

write_state(io::IO, state) = bson(io, state)
