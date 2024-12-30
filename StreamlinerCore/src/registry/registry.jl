# Registry management

"""
    Registry{P}(uri::String, database::String, connection::String)

Initialize a MongoDB to store outcomes of training, validation, and finetuning runs,
as well as the location of saved model weights.
`P` denotes the type of paths to model weights.
`String` is the default, but other options are possible (e.g., `AWWS3.S3Path`).
"""
struct Registry{P}
    uri::String
    database::String
    collection::String
end

function Registry(uri::AbstractString, database::AbstractString, collection::AbstractString)
    return Registry{String}(uri, database, collection)
end

function Base.open(f::Function, registry::Registry)
    # initialize client
    client = Client(registry.uri)
    # access database
    database = client[registry.database]
    # access collection
    collection = database[registry.collection]
    # compute function
    result = f(collection)
    # finalize client
    destroy!(client)

    return result
end

read_state(io::IO) = load(io)
# Fallback for non-standard paths, e.g., S3 paths
read_state(path) = read_state(IOBuffer(read(path)))

write_state(io::IO, state) = bson(io, state)

get_metadata(d::AbstractDict) = d

function to_key(
        model, training, data, entry::Maybe{BSON} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )

    return BSON(
        "model" => get_metadata(model),
        "training" => get_metadata(training),
        "data" => get_metadata(data),
        "from" => isnothing(entry) ? nothing : entry["_id"],
        "trained" => trained,
        "resumed" => resumed,
    )
end

function insert_entry(
        registry::Registry, result::AbstractDict,
        model::Model, training::Training, data::AbstractData,
        entry::Maybe{BSON} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )

    return open(registry) do collection
        summary = get_summary(data)
        templates = templates2dict(get_templates(data))
        key = to_key(model, training, data, entry; trained, resumed)
        document = BSON(
            key...,
            "result" => result,
            "summary" => summary,
            "templates" => templates,
            "time" => now()
        )
        insertion_result = insert_one(collection, document)
        return BSON("_id" => insertion_result.inserted_oid, document...)
    end
end

function find_entries(registry::Registry, filter::BSON; options = nothing)
    open(registry) do collection
        entries = find(collection, filter; options)
        collect(entries)
    end
end

function find_entry(registry::Registry, filter::BSON; options = nothing)
    open(registry) do collection
        find_one(collection, filter; options)
    end
end

"""
    find_all_entries(
        registry::Registry, model, training, data,
        entry::Maybe{BSON} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )

Find all entries in registry for the given configuration.
`entry` should be `nothing` when looking for the result of `train`,
whereas it should be the starting entry when looking for the result
of `validate` or `finetune`.
`trained` should be set to `false` only when looking for the result of `validate`.
"""
function find_all_entries(
        registry::Registry, model, training, data,
        entry::Maybe{BSON} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )
    key = to_key(model, training, data, entry; trained, resumed)
    filter = to_query(key)
    return find_entries(registry, filter)
end

"""
    find_latest_entry(
        registry::Registry, model, training, data,
        entry::Maybe{BSON} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )

Find the latest entry in registry for the given configuration.
`entry` should be `nothing` when looking for the result of `train`,
whereas it should be the starting entry when looking for the result
of `validate` or `finetune`.
`trained` should be set to `false` only when looking for the result of `validate`.
"""
function find_latest_entry(
        registry::Registry, model, training, data,
        entry::Maybe{BSON} = nothing;
        trained::Bool = true, resumed::Maybe{Bool} = trained ? false : nothing
    )
    options = BSON("sort" => Dict("time" => -1))
    key = to_key(model, training, data, entry; trained, resumed)
    filter = to_query(key)
    return find_entry(registry, filter; options)
end

"""
    replace_prefix(registry::Registry, new::AbstractString)

Update `prefix` in all entries in the registry to `new`.
"""
replace_prefix(registry::Registry, new::AbstractString) = replace_prefix(registry, nothing => new)

"""
    replace_prefix(registry::Registry, old::AbstractString => new::AbstractString)

Update `prefix` in entries in the registry from `old` to `new`.
Entries where `prefix` is different from `old` are left unchanged.
"""
function replace_prefix(registry::Registry, (old, new)::Pair{<:Maybe{AbstractString}, <:AbstractString})
    open(registry) do collection
        selector = isnothing(old) ? BSON() : BSON("result.prefix" => old)
        update = BSON("\$set" => StringDict("result.prefix" => new))
        update_many(collection, selector, update)
    end
end

"""
    has_weights(entry::BSON)

Return `true` if `entry` is a successful training entry, `false` otherwise
"""
function has_weights(entry::BSON)
    result = entry["result"]
    !isnothing(get(result, "path", nothing))
end
