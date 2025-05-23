@kwdef struct DBData{N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    order_by::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
end

struct Processor{N, D}
    data::DBData{N}
    device::D
    id::String
end

function (p::Processor)(cols)
    (; predictors, targets) = p.data
    extract_column(k) = Tables.getcolumn(cols, Symbol(k))
    input::Array{Float32, 2} = stack(extract_column, predictors, dims = 1)
    target::Array{Float32, 2} = stack(extract_column, targets, dims = 1)
    id::Vector{Int64} = Tables.getcolumn(cols, Symbol(p.id))
    return (; id, input = p.device(input), target = p.device(target))
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
        "order_by" => data.order_by,
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
    (; repository, schema, order_by, partition) = data

    if isnothing(batchsize)
        throw(ArgumentError("Unbatched streaming is not supported."))
    end

    nrows = StreamlinerCore.get_nsamples(data, i)
    ns = colnames(data.repository, data.table; data.schema)
    id_col = get_id_col(ns)

    with_connection(repository) do con
        catalog = get_catalog(repository; schema)
        sorters = shuffle ? [Fun.random()] : Get.(order_by)
        stream_query = id_table(data.table, id_col) |>
            filter_partition(partition, i) |>
            Order(by = sorters)

        if shuffle
            seed = 2rand(rng) - 1
            seed_query = Select(Fun.setseed(Var.seed))
            sql, ps = render_params(catalog, seed_query, (; seed))
            DBInterface.execute(Returns(nothing), con, sql, ps)
        end

        stream_sql, _ = render_params(catalog, stream_query)
        result = DBInterface.execute(con, stream_sql, StreamResult)

        try
            batches = Batches(result, batchsize, nrows)
            stream = Iterators.map(Processor(data, device, id_col), batches)
            f(stream)
        finally
            DBInterface.close!(result)
        end
    end
end

function append_batch(appender::DuckDBUtils.Appender, id, v)
    for i in eachindex(id)
        DuckDBUtils.append(appender, id[i])
        for j in axes(v, 1)
            DuckDBUtils.append(appender, v[j, i])
        end
        DuckDBUtils.end_row(appender)
    end
end

function StreamlinerCore.ingest(data::DBData{1}, eval_stream, select; suffix, destination)
    select == (:prediction,) || throw(ArgumentError("Custom selection is not supported"))
    ns = colnames(data.repository, data.table; data.schema)
    id_col = get_id_col(ns)

    tmp = string(uuid4())

    tbl = SimpleTable()
    tbl[id_col] = Int64[]
    for k in data.targets
        tbl[k] = Float32[]
    end
    load_table(data.repository, tbl, tmp; data.schema)

    appender = DuckDBUtils.Appender(data.repository.db, tmp, data.schema)
    for batch in eval_stream
        v = collect(batch.prediction)
        append_batch(appender, batch.id, v)
    end
    DuckDBUtils.close(appender)

    new_vars = join_names.(data.targets, suffix) .=> Get.(data.targets, over = Get.eval)
    # avoid selecting overlapping columns (TODO: is this needed?)
    old_ns = setdiff(ns, first.(new_vars))
    old_vars = old_ns .=> Get.(old_ns)
    join_clause = Join(
        "eval" => From(tmp),
        on = Get(id_col) .== Get(id_col, over = Get.eval),
        right = true
    )
    query = id_table(data.table, id_col) |>
        join_clause |>
        Select(old_vars..., new_vars...)
    replace_table(data.repository, query, destination; data.schema)
    delete_table(data.repository, tmp; data.schema)
end
