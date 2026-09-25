abstract type Funnel end

get_helper_table_keys(::Funnel) = (tables = String[], files = String[])

@kwarg struct TableSpec
    repository::Repository
    schema::Maybe{String}
    table::String
    id_var::String
end

mutable struct FunneledData{F <: Funnel, N} <: AbstractData{N}
    const table_spec::TableSpec
    const funnel::F
    const partition::Maybe{String}
    const require_targets::Bool
    # FIXME: initialize to `nothing`?
    # be mindful of type instability
    unique_values::Dict{String, AbstractVector}
    helper_tables::Maybe{Dict{String, String}}
    helper_files::Maybe{Dict{String, String}}
end

function FunneledData(
        ::Val{N}, funnel::F, table_spec::TableSpec;
        partition::Maybe{AbstractString},
        require_targets::Bool = true,
        unique_values::AbstractDict = Dict{String, AbstractVector}(),
        helper_tables::Maybe{AbstractDict} = nothing,
        helper_files::Maybe{AbstractDict} = nothing
    ) where {F <: Funnel, N}

    return FunneledData{F, N}(
        table_spec, funnel, partition,
        require_targets, unique_values,
        helper_tables, helper_files
    )
end

function initialize_helper_tables!(data::FunneledData; tables::AbstractDict, files::AbstractDict)
    # check that keys of `d` match `get_helper_table_keys(data.funnel)`
    expected_keys = get_helper_table_keys(data.funnel)
    if !issetequal(expected_keys.tables, keys(tables))
        msg = "Incorrect table keys: expected $(expected_keys), found $(collect(keys(tables)))."
        throw(ArgumentError(msg))
    end
    if !issetequal(expected_keys.files, keys(files))
        msg = "Incorrect file keys: expected $(expected_keys), found $(collect(keys(files)))."
        throw(ArgumentError(msg))
    end

    data.helper_tables = tables
    data.helper_files = files

    return initialize_helper_tables(data)
end

initialize_helper_tables(data::FunneledData) = data

# TODO: support transforms in the schema
const RICH_VARIABLES_DEF = VARIABLES_DEF

# Interface:
#
# An implementation of a `FunnelType <: Funnel` must include:
# - accessors on `fn::FunnelType`
#   - `get_helpers_in`
#   - `get_helpers_out`
#   - `get_order_by`
#   - `get_inputs`
#   - `get_constant_inputs`
#   - `get_input_paths`
#   - `get_targets`
#   - `get_constant_targets`
#   - `get_target_paths`
# - `get_metadata` on `fn::FunnelType`
# - `get_helper_table_keys` on `fn::FunnelType` (optional)
# - `get_nsamples` on `data::FunneledData{FunnelType}`
# - `get_templates` on `data::FunneledData{FunnelType}`
# - `stream` on `data::FunneledData{FunnelType}`
# - `ingest` on `data::FunneledData{FunnelType}`
# - `initialize_helper_tables` on `data::FunneledData{FunnelType}` (optional)

# TODO: integrate with StructUtils tags to get fully specified schema
@kwarg struct DBFunnel <: Funnel
    order_by::Vector{String} & (dashi = NONEMPTY_VARIABLES_DEF,)
    inputs::Vector{RichColumn} = RichColumn[] & (dashi = RICH_VARIABLES_DEF,)
    input_paths::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    targets::Vector{RichColumn} = RichColumn[] & (dashi = RICH_VARIABLES_DEF,)
    target_paths::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
end

get_helpers_in(dbf::DBFunnel) = String[]
get_helpers_out(dbf::DBFunnel) = String[]
get_order_by(dbf::DBFunnel) = dbf.order_by

get_inputs(dbf::DBFunnel) = dbf.inputs
get_constant_inputs(dbf::DBFunnel) = String[]
get_input_paths(dbf::DBFunnel) = dbf.input_paths

get_targets(dbf::DBFunnel) = dbf.targets
get_constant_targets(dbf::DBFunnel) = String[]
get_target_paths(dbf::DBFunnel) = dbf.target_paths

# FIXME: add checks that either inputs or input_paths are present
# and similarly for outputs and output_paths
DBFunnel(d::AbstractDict) = DashiBase.construct(DBFunnel, d)

function get_metadata(dbf::DBFunnel)
    c = DashiBase.to_config(dbf)

    return StringDict(
        "order_by" => dbf.order_by,
        "inputs" => get_metadata.(dbf.inputs),
        "input_paths" => dbf.input_paths,
        "targets" => get_metadata.(dbf.targets),
        "target_paths" => dbf.target_paths,
    )
end

struct Processor{N, D}
    data::FunneledData{DBFunnel, N}
    device::D
    id::String
end

function transform!(
        arr::AbstractArray{T, N}, vars::AbstractVector, unique_values::AbstractDict
    ) where {T <: Number, N}

    # TODO: avoid having to check `haskey` several times
    idxs = column_indices(Iterators.map(colname, vars), unique_values)
    for (I, var) in zip(idxs, vars)
        if haskey(unique_values, colname(var))
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

function encode_transform(cols, vars::AbstractVector, unique_values::AbstractDict)
    arr = encode_columns(cols, Iterators.map(colname, vars), unique_values)
    transform!(arr, vars, unique_values)
    return arr
end

# TODO: also create tensor of paths if any of `input_paths` or `target_paths` is not `nothing`
function (p::Processor)(cols)
    (; funnel, require_targets, unique_values) = p.data
    (; inputs, targets) = funnel
    input::Array{Float32, 2} = encode_transform(cols, inputs, unique_values)
    target::Maybe{Array{Float32, 2}} = if require_targets
        encode_transform(cols, targets, unique_values)
    else
        nothing
    end
    _id::Vector{Int64} = Tables.getcolumn(cols, Symbol(p.id))
    return (; _id, input = p.device(input), target = p.device(target))
end

function get_templates(data::FunneledData{DBFunnel})
    (; funnel, unique_values) = data
    input_names, target_names = colname.(funnel.inputs), colname.(funnel.targets)
    n_inputs = sum(Fix2(column_number, unique_values), input_names)
    n_targets = sum(Fix2(column_number, unique_values), target_names)
    input = Template(Float32, (n_inputs,))
    target = Template(Float32, (n_targets,))
    return (; input, target)
end

get_partition_cond(::Nothing, i::Integer) = Lit(i == 1)
get_partition_cond(partition::AbstractString, i::Integer) = (Get(partition) .== i)

function get_nsamples(data::FunneledData{DBFunnel}, i::Integer)
    (; table_spec, partition) = data
    (; repository, schema, table) = table_spec
    cond = get_partition_cond(partition, i)
    q = From(table) |>
        Where(cond) |>
        Group() |>
        Select("Count" => Agg.count())
    return DBInterface.execute(to_nrow, repository, q; schema)
end

function stream(f, data::FunneledData{DBFunnel}, i::Integer, streaming::Streaming)
    (; device, batchsize, shuffle, rng) = streaming
    (; table_spec, funnel, partition) = data
    (; repository, schema, table, id_var) = table_spec

    if isnothing(batchsize)
        throw(ArgumentError("Unbatched streaming is not supported."))
    end

    nrows = get_nsamples(data, i)

    return with_connection(repository) do con
        catalog = get_catalog(con; schema)
        sorters = shuffle ? [Fun.random()] : Get.(funnel.order_by)
        cond = get_partition_cond(partition, i)
        stream_query = From(table) |>
            Where(cond) |>
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

function ingest(
        data::FunneledData{DBFunnel, 1}, eval_stream, select::Union{AbstractVector, Tuple};
        suffix::AbstractString, destination::AbstractString
    )

    select == (:prediction,) || throw(ArgumentError("Custom selection is not supported"))

    targets = colname.(get_targets(data.funnel))
    output_names::Vector{String} = String[join((tgt, suffix), "_") for tgt in targets]
    output_types::Vector{Type} = Type[column_type(tgt, data.unique_values) for tgt in targets]
    (; repository, schema, id_var) = data.table_spec

    initialize_table(
        repository,
        vcat(String[id_var], output_names),
        vcat(Type[Int64], output_types),
        destination;
        schema
    )

    with_appender(repository, destination; schema) do appender
        for batch in eval_stream
            v = collect(batch.prediction)
            append_batch(appender, batch._id, decode_columns(v, targets, data.unique_values))
        end
    end

    return output_names
end
