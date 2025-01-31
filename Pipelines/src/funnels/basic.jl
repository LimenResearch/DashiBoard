@kwdef struct DBData{N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    sorters::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
end

struct Processor{N, D}
    data::DBData{N}
    device::D
end

# TODO: consider adding ID field?

function (p::Processor)(cols)
    (; predictors, targets) = p.data
    extract_column(k) = Tables.getcolumn(cols, Symbol(k))
    input::Array{Float32, 2} = stack(extract_column, predictors, dims = 1)
    target::Array{Float32, 2} = stack(extract_column, targets, dims = 1)
    return (; input, target)
end

function StreamlinerCore.get_templates(data::DBData)
    input = Template(Float32, (length(data.predictors),))
    target = Template(Float32, (length(data.targets),))
    return (; input, target)
end

# TODO: understand role of `get_metadata` in the presence of cards?
function StreamlinerCore.get_metadata(data::DBData)
    return Dict(
        "schema" => data.schema,
        "table" => data.table,
        "sorters" => data.sorters,
        "predictors" => data.predictors,
        "targets" => data.targets,
        "partition" => data.partition
    )
end

function StreamlinerCore.get_nsamples(data::DBData, i::Int)
    (; repository, schema, partition, table) = data
    q = From(table) |>
        filter_partition(partition, i) |>
        Group() |>
        Select("count" => Agg.count())
    return DBInterface.execute(x -> only(x).count, repository, q; schema)
end

function StreamlinerCore.stream(f, data::DBData, i::Int, streaming::Streaming)
    (; device, batchsize, shuffle, rng) = streaming
    (; repository, schema, partition, table) = data

    if isnothing(batchsize)
        throw(ArgumentError("Unbatched streaming is not supported."))
    end

    nrows = StreamlinerCore.get_nsamples(data, i)

    with_connection(repository) do con
        catalog = get_catalog(repository; schema)
        order_by = shuffle ? [Fun.random()] : Get.(data.sorters)
        stream_query = From(table) |>
            filter_partition(partition, i) |>
            Order(by = order_by)

        if shuffle
            seed = 2rand(rng) - 1
            seed_query = Select(Fun.setseed(Var.seed))
            sql, ps = render_params(catalog, seed_query, (; seed))
            DBInterface.execute(Returns(nothing), con, sql, ps)
        end

        stream_sql, _ = render_params(catalog, stream_query)
        result = DBInterface.execute(con, stream_sql, StreamResult)

        try
            batches = Batches(Tables.partitions(result), batchsize, nrows)
            stream = Iterators.map(Processor(data, device), batches)
            f(stream)
        finally
            DBInterface.close!(result)
        end
    end
end
