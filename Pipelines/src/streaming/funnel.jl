struct FunneledData{F <: Funnel, N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    id_var::PrimaryKey # TODO: determine if this belong here?
    funnel::F
    partition::Union{String, Nothing}
    require_targets::Bool
    uvals::Dict{String, AbstractVector}
end

function FunneledData(
        ::Val{N}, funnel::F;
        repository::Repository,
        schema::Union{AbstractString, Nothing},
        table::AbstractString,
        id_var::AbstractPrimaryKey,
        partition::Union{AbstractString, Nothing},
        require_targets::Bool = true,
        uvals::AbstractDict = Dict{String, AbstractVector}()
    ) where {F <: Funnel, N}

    return FunneledData{F, N}(
        repository, schema, table, id_var,
        funnel, partition, require_targets, uvals
    )
end

# Note: `uvals` might be invalidated by this
function FunneledData{F, N}(
        fd::FunneledData, funnel::F = fd.funnel;
        repository::Repository = fd.repository,
        schema::Union{AbstractString, Nothing} = fd.schema,
        table::AbstractString = fd.table,
        id_var::AbstractPrimaryKey = fd.id_var,
        partition::Union{AbstractString, Nothing} = fd.partition,
        require_targets::Bool = fd.require_targets,
        uvals::AbstractDict = fd.uvals
    ) where {F <: Funnel, N}

    return FunneledData{F, N}(
        repository, schema, table, id_var,
        funnel, partition, require_targets, uvals
    )
end

function compute_unique_values!(data::FunneledData)
    (; repository, table, schema, funnel, partition, uvals) = data
    inputs, constant_inputs = SC.get_inputs(funnel), SC.get_constant_inputs(funnel)
    targets, constant_targets = SC.get_targets(funnel), SC.get_constant_targets(funnel)
    input_names, target_names = SC.colname.(inputs), SC.colname.(targets)

    empty!(uvals)
    src = From(table) |> filter_partition(partition)
    schm = DBInterface.execute(Tables.schema, repository, src |> Limit(0); schema)
    cols = union(input_names, constant_inputs, target_names, constant_targets)
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

# Interface:
#
# An implementation of a `FunnelType <: Funnel` must include:
# - SC accessors on `fn::FunnelType`
#   - `get_helpers`
#   - `get_order_by`
#   - `get_inputs`
#   - `get_constant_inputs`
#   - `get_input_paths`
#   - `get_targets`
#   - `get_constant_targets`
#   - `get_target_paths`
# - `SC.get_metadata` on `fn::FunnelType`
# - `SC.get_nsamples` on `data::FunneledData{FunnelType}`
# - `SC.get_templates` on `data::FunneledData{FunnelType}`
# - `SC.stream` on `data::FunneledData{FunnelType}`
# - `SC.ingest` on `data::FunneledData{FunnelType}`

# Specific implementation for `DBFunnel`

struct Processor{N, D}
    data::FunneledData{DBFunnel, N}
    device::D
    id::String
end

function transform!(
        arr::AbstractArray{T, N}, vars::AbstractVector, uvals::AbstractDict
    ) where {T <: Number, N}

    # TODO: avoid having to check `haskey` several times
    idxs = column_indices(Iterators.map(SC.colname, vars), uvals)
    for (I, var) in zip(idxs, vars)
        if haskey(uvals, SC.colname(var))
            if var.transform !== identity
                throw(ArgumentError("Transformation of one-hot encoded variable is not supported"))
            end
        else
            idx = only(I)
            slice = selectdim(arr, N - 1, idx)
            copy!(slice, var.transform(slice))
        end
    end
    return arr
end

function encode_transform(cols, vars::AbstractVector, uvals::AbstractDict)
    arr = encode_columns(cols, Iterators.map(SC.colname, vars), uvals)
    transform!(arr, vars, uvals)
    return arr
end

# TODO: also create tensor of paths if any of `input_paths` or `target_paths` is not `nothing`
function (p::Processor)(cols)
    (; funnel, require_targets, uvals) = p.data
    (; inputs, targets) = funnel
    input::Array{Float32, 2} = encode_transform(cols, inputs, uvals)
    target::Union{Array{Float32, 2}, Nothing} = if require_targets
        encode_transform(cols, targets, uvals)
    else
        nothing
    end
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
        suffix::AbstractString, destination
    )
    select == (:prediction,) || throw(ArgumentError("Custom selection is not supported"))

    targets = SC.colname.(SC.get_targets(data.funnel))
    output_names = join_names.(targets, Ref(suffix))
    output_types = column_type.(targets, Ref(data.uvals))

    tbl = SimpleTable(data.id_var => Int64[])
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
