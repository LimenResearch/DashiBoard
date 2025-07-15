@kwdef struct DBData{N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    order_by::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
    uvals::Dict{String, AbstractVector} = Dict{String, AbstractVector}()
end

function train!(data::DBData)
    (; repository, table, schema, predictors, targets, partition, uvals) = data

    empty!(uvals)
    src = From(table) |> filter_partition(partition)
    schm = DBInterface.execute(Tables.schema, repository, src |> Limit(0); schema)
    cols = union(predictors, targets)
    idxs = indexin(Symbol.(cols), collect(schm.names))

    for (i, k) in zip(idxs, cols)
        T = schm.types[i]
        if !(nonmissingtype(T) <: Number) # TODO: what to do with booleans?
            q = src |> Group(Get(k)) |> Select(Get(k)) |> Order(Get(k))
            v = DBInterface.execute(Fix1(map, first), repository, q; schema)
            uvals[k] = v
        end
    end

    return data
end

struct Processor{N, D}
    data::DBData{N}
    device::D
    id::String
end

function (p::Processor)(cols)
    (; predictors, targets, uvals) = p.data
    input::Array{Float32, 2} = encode_columns(cols, predictors, uvals)
    target::Array{Float32, 2} = encode_columns(cols, targets, uvals)
    id::Vector{Int64} = Tables.getcolumn(cols, Symbol(p.id))
    return (; id, input = p.device(input), target = p.device(target))
end

function StreamlinerCore.get_templates(data::DBData)
    (; predictors, targets, uvals) = data
    n_predictors = sum(Fix2(column_number, uvals), predictors)
    n_targets = sum(Fix2(column_number, uvals), targets)
    input = Template(Float32, (n_predictors,))
    target = Template(Float32, (n_targets,))
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
        Select("Count" => Agg.count())
    return DBInterface.execute(to_nrow, repository, q; schema)
end

function StreamlinerCore.stream(f, data::DBData, i::Int, streaming::Streaming)
    (; device, batchsize, shuffle, rng) = streaming
    (; repository, schema, order_by, partition) = data

    if isnothing(batchsize)
        throw(ArgumentError("Unbatched streaming is not supported."))
    end

    nrows = StreamlinerCore.get_nsamples(data, i)
    ns = colnames(data.repository, data.table; data.schema)
    id_var = new_name("id", ns)
    id_table = with_id(data.table, id_var)

    return with_connection(repository) do con
        catalog = get_catalog(repository; schema)
        sorters = shuffle ? [Fun.random()] : Get.(order_by)
        stream_query = id_table |>
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
            stream = Iterators.map(Processor(data, device, id_var), batches)
            f(stream)
        finally
            DBInterface.close!(result)
        end
    end
end

function append_batch(appender::DuckDBUtils.Appender, id, vs)
    for i in eachindex(id)
        DuckDBUtils.append(appender, id[i])
        for v in vs
            DuckDBUtils.append(appender, v[i])
        end
        DuckDBUtils.end_row(appender)
    end
    return
end

function StreamlinerCore.ingest(data::DBData{1}, eval_stream, select; suffix, destination)
    select == (:prediction,) || throw(ArgumentError("Custom selection is not supported"))
    ns = colnames(data.repository, data.table; data.schema)
    id_var = new_name("id", ns, data.targets)
    id_table = with_id(data.table, id_var)

    tmp = string(uuid4())

    tbl = SimpleTable()
    tbl[id_var] = Int64[]
    for k in data.targets
        T = column_type(k, data.uvals)
        tbl[k] = T[]
    end
    load_table(data.repository, tbl, tmp; data.schema)

    appender = DuckDBUtils.Appender(data.repository.db, tmp, data.schema)
    for batch in eval_stream
        v = collect(batch.prediction)
        append_batch(appender, batch.id, decode_columns(v, data.targets, data.uvals))
    end
    DuckDBUtils.close(appender)

    new_vars = join_names.(data.targets, suffix) .=> Get.(data.targets, over = Get.eval)
    # avoid selecting overlapping columns (TODO: is this needed?)
    old_ns = setdiff(ns, first.(new_vars))
    old_vars = old_ns .=> Get.(old_ns)
    join_clause = Join(
        "eval" => From(tmp),
        on = Get(id_var) .== Get(id_var, over = Get.eval),
        right = true
    )
    query = id_table |>
        join_clause |>
        Select(old_vars..., new_vars...)
    replace_table(data.repository, query, destination; data.schema)
    # TODO: finally block to ensure table gets deleted
    delete_table(data.repository, tmp; data.schema)
    return
end
