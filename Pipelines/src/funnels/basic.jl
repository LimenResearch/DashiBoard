@kwdef struct DBData{N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    id_var::PrimaryKey # TODO: determine if this belong here?
    data_spec::DataSpec
    uvals::Dict{String, AbstractVector} = Dict{String, AbstractVector}()
end

function train!(data::DBData)
    (; repository, table, schema, data_spec, uvals) = data
    inputs, targets = input_names(data_spec), target_names(data_spec)

    empty!(uvals)
    src = From(table) |> filter_partition(data_spec.partition)
    schm = DBInterface.execute(Tables.schema, repository, src |> Limit(0); schema)
    cols = union(inputs, targets)
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

function get_evaluation_data(
        ::Funnel{Nothing}, data_spec::DataSpec;
        repository, schema, table, id_var, uvals
    )
    return DBData{1}(; repository, schema, table, id_var, data_spec, uvals)
end

function get_partitioned_data(
        ::Funnel{Nothing}, data_spec::DataSpec;
        repository, schema, table, id_var
    )
    data = DBData{2}(; repository, schema, table, id_var, data_spec)
    train!(data)
    return data
end

struct Processor{N, D}
    data::DBData{N}
    device::D
    id::String
end

function (p::Processor)(cols)
    (; data_spec, uvals) = p.data
    inputs, targets = input_names(data_spec), target_names(data_spec)
    input::Array{Float32, 2} = encode_columns(cols, inputs, uvals)
    target::Array{Float32, 2} = encode_columns(cols, targets, uvals)
    id::Vector{Int64} = Tables.getcolumn(cols, Symbol(p.id))
    return (; id, input = p.device(input), target = p.device(target))
end

function SC.get_templates(data::DBData)
    (; data_spec, uvals) = data
    inputs, targets = input_names(data_spec), target_names(data_spec)
    n_inputs = sum(Fix2(column_number, uvals), inputs)
    n_targets = sum(Fix2(column_number, uvals), targets)
    input = Template(Float32, (n_inputs,))
    target = Template(Float32, (n_targets,))
    return (; input, target)
end

function SC.get_nsamples(data::DBData, i::Int)
    (; repository, schema, table, data_spec) = data
    q = From(table) |>
        filter_partition(data_spec.partition, i) |>
        Group() |>
        Select("Count" => Agg.count())
    return DBInterface.execute(to_nrow, repository, q; schema)
end

function SC.stream(f, data::DBData, i::Int, streaming::Streaming)
    (; device, batchsize, shuffle, rng) = streaming
    (; repository, schema, id_var, data_spec) = data
    (; order_by, partition) = data_spec

    if isnothing(batchsize)
        throw(ArgumentError("Unbatched streaming is not supported."))
    end

    nrows = SC.get_nsamples(data, i)

    return with_connection(repository) do con
        catalog = get_catalog(repository; schema)
        sorters = shuffle ? [Fun.random()] : Get.(order_by)
        stream_query = From(data.table) |>
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

function SC.ingest(data::DBData{1}, eval_stream, select; suffix::AbstractString, destination, id)
    select == (:prediction,) || throw(ArgumentError("Custom selection is not supported"))

    targets = target_names(data.data_spec)
    output_names = join_names.(targets, Ref(suffix))
    output_types = column_type.(targets, Ref(data.uvals))

    tbl = SimpleTable(id => Int64[])
    for (output_name, output_type) in zip(output_names, output_types)
        tbl[output_name] = output_type[]
    end
    load_table(data.repository, tbl, destination; data.schema)

    appender = DuckDBUtils.Appender(data.repository.db, destination, data.schema)
    for batch in eval_stream
        v = collect(batch.prediction)
        append_batch(appender, batch.id, decode_columns(v, targets, data.uvals))
    end
    DuckDBUtils.close(appender)
    return output_names
end
