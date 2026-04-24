struct FunneledData{F <: Funnel, N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    id_var::PrimaryKey # TODO: determine if this belong here?
    funnel::F
    partition::Union{String, Nothing}
    uvals::Dict{String, AbstractVector}
end

function FunneledData(
        ::Val{N}, funnel::F;
        repository::Repository,
        schema::Union{AbstractString, Nothing},
        table::AbstractString,
        id_var::AbstractPrimaryKey,
        partition::Union{AbstractString, Nothing},
        uvals::AbstractDict = Dict{String, AbstractVector}()
    ) where {F <: Funnel, N}

    return FunneledData{F, N}(repository, schema, table, id_var, funnel, partition, uvals)
end

# Fallbacks

sorting_vars(dbf::Funnel) = dbf.order_by
helper_vars(::Funnel) = String[]
input_vars(dbf::Funnel) = SC.colname.(dbf.inputs)
input_path_var(dbf::Funnel) = dbf.input_paths
target_vars(dbf::Funnel) = SC.colname.(dbf.targets)
target_path_var(dbf::Funnel) = dbf.target_paths

# DBFunnel implementation

function train!(data::FunneledData{DBFunnel}) # TODO: generalize?
    (; repository, table, schema, funnel, partition, uvals) = data
    (; inputs, targets) = funnel
    input_names, target_names = SC.colname.(inputs), SC.colname.(targets)

    empty!(uvals)
    src = From(table) |> filter_partition(partition)
    schm = DBInterface.execute(Tables.schema, repository, src |> Limit(0); schema)
    cols = union(input_names, target_names)
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
    data::FunneledData{DBFunnel, N}
    device::D
    id::String
end

function (p::Processor)(cols)
    (; funnel, uvals) = p.data
    (; inputs, targets) = funnel
    input::Array{Float32, 2} = encode_columns(cols, SC.colname.(inputs), uvals)
    target::Array{Float32, 2} = encode_columns(cols, SC.colname.(targets), uvals)
    # FIXME: apply transform!
    id::Vector{Int64} = Tables.getcolumn(cols, Symbol(p.id))
    return (; id, input = p.device(input), target = p.device(target))
end

function SC.get_templates(data::FunneledData{DBFunnel})
    (; funnel, uvals) = data
    input_names, target_names = SC.colname.(funnel.inputs), SC.colname.(funnel.targets)
    n_inputs = sum(Fix2(column_number, uvals), input_names)
    n_targets = sum(Fix2(column_number, uvals), target_names)
    input = Template(Float32, (n_inputs,))
    target = Template(Float32, (n_targets,))
    return (; input, target)
end

function SC.get_nsamples(data::FunneledData{DBFunnel}, i::Int)
    (; repository, schema, table, partition) = data
    q = From(table) |>
        filter_partition(partition, i) |>
        Group() |>
        Select("Count" => Agg.count())
    return DBInterface.execute(to_nrow, repository, q; schema)
end

function SC.stream(f, data::FunneledData{DBFunnel}, i::Int, streaming::Streaming)
    (; device, batchsize, shuffle, rng) = streaming
    (; repository, schema, id_var, funnel, partition) = data

    if isnothing(batchsize)
        throw(ArgumentError("Unbatched streaming is not supported."))
    end

    nrows = SC.get_nsamples(data, i)

    return with_connection(repository) do con
        catalog = get_catalog(repository; schema)
        sorters = shuffle ? [Fun.random()] : Get.(funnel.order_by)
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

function SC.ingest(
        data::FunneledData{DBFunnel, 1}, eval_stream, select;
        suffix::AbstractString, destination, id_var
    )
    select == (:prediction,) || throw(ArgumentError("Custom selection is not supported"))

    targets = target_vars(data.funnel)
    output_names = join_names.(targets, Ref(suffix))
    output_types = column_type.(targets, Ref(data.uvals))

    tbl = SimpleTable(id_var => Int64[])
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
