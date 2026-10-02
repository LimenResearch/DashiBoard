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

# The transforms an author may give the columns of `list`, by resolved column name.
transform_map(list::AbstractString) = MapIR(values = StringIR(enum = transform_names()), keys_from = list)

"""
    DBFunnel(; order_by, inputs, input_transforms, targets, target_transforms, loader)

Rows of a table, in `order_by` order, as model inputs and targets.

`inputs` and `targets` name columns. A column is passed through the transform its map gives it,
and as it is when the map does not mention it; the two maps are separate because one column may be
both an input and a target. `loader` says how a row is read: as it is, or as a tensor from a file.

The fields are in the order a form draws them, each map under its list.
"""
@kwarg struct DBFunnel <: Funnel
    order_by::Vector{String} & (dashi = NONEMPTY_VARIABLES_DEF,)
    inputs::Vector{String} = String[] & (dashi = VARIABLES_DEF,)
    input_transforms::Dict{String, String} = Dict{String, String}() & (dashi = transform_map("inputs"),)
    targets::Vector{String} = String[] & (dashi = VARIABLES_DEF,)
    target_transforms::Dict{String, String} = Dict{String, String}() & (dashi = transform_map("targets"),)
    loader::Loader = RowLoader() & (dashi = loader_IR(),)
end

# Two funnels built from the same document are the same funnel.
function Base.:(==)(a::DBFunnel, b::DBFunnel)
    return all(getfield(a, f) == getfield(b, f) for f in fieldnames(DBFunnel))
end
Base.hash(f::DBFunnel, h::UInt) = foldr(hash, ntuple(i -> getfield(f, i), fieldcount(DBFunnel)); init = h)

# With the default loader the rows are the columns, so there must be some on each side; a loader
# that reads files may stand in for them. An absent `loader` is the default, and satisfies the
# condition as written.
function DashiBase.constraints(::Type{DBFunnel})
    rule = StringDict(
        "if" => StringDict(
            "properties" => StringDict(
                "loader" => StringDict("properties" => StringDict("type" => StringDict("const" => "")))
            )
        ),
        "then" => StringDict(
            "properties" => StringDict(
                "inputs" => DashiBase.json_schema(NONEMPTY_VARIABLES_DEF),
                "targets" => DashiBase.json_schema(NONEMPTY_VARIABLES_DEF),
            ),
            "required" => ["inputs", "targets"],
        ),
    )
    return StringDict[rule]
end

get_helpers_in(dbf::DBFunnel) = String[]
get_helpers_out(dbf::DBFunnel) = String[]
get_order_by(dbf::DBFunnel) = dbf.order_by

rich_columns(names, transforms) = RichColumn[RichColumn(name, get(transforms, name, "identity")) for name in names]

get_inputs(dbf::DBFunnel) = rich_columns(dbf.inputs, dbf.input_transforms)
get_constant_inputs(dbf::DBFunnel) = String[]
get_input_paths(dbf::DBFunnel) = input_paths(dbf.loader)

get_targets(dbf::DBFunnel) = rich_columns(dbf.targets, dbf.target_transforms)
get_constant_targets(dbf::DBFunnel) = String[]
get_target_paths(dbf::DBFunnel) = target_paths(dbf.loader)

# What a document cannot be checked for by its schema: a transform's key has to be one of the
# columns of its list, and which columns those are is only known once the selectors are resolved.
function validate(dbf::DBFunnel)
    if isempty(dbf.order_by)
        throw(ArgumentError("User must define sorting variable(s)"))
    end
    if isempty(dbf.targets) && isnothing(get_target_paths(dbf))
        throw(ArgumentError("User must define target variable(s) or target paths"))
    end
    if isempty(dbf.inputs) && isnothing(get_input_paths(dbf))
        throw(ArgumentError("User must define input variable(s) or input paths"))
    end
    for (list, names, transforms) in (
            ("inputs", dbf.inputs, dbf.input_transforms), ("targets", dbf.targets, dbf.target_transforms),
        )
        for key in sort!(collect(keys(transforms)))
            key in names || throw(
                TransformError(
                    "`$(key)` is not among the $(list) of this funnel, so it cannot be transformed",
                    [transform_field(list), key]
                )
            )
        end
    end
    return dbf
end

"""
    funnel_IR(F)

The schema of funnel type `F`: its tagged fields. A funnel that wraps another says so here, with
[`flat_IR`](@ref).
"""
funnel_IR(::Type{F}) where {F <: Funnel} = ObjectIR(F)

"""
    make_funnel(F, d::AbstractDict)

The funnel of type `F` a document describes. A funnel that wraps another splits the document here,
with [`split_config`](@ref).
"""
function make_funnel(::Type{DBFunnel}, d::AbstractDict)
    haskey(d, "order_by") || throw(ArgumentError("User must define sorting variable(s)"))
    return validate(DashiBase.construct(DBFunnel, d))
end

# The document form: nothing for a transform nobody named, nothing for the default loader.
function get_metadata(dbf::DBFunnel)
    d = StringDict("order_by" => dbf.order_by, "inputs" => dbf.inputs, "targets" => dbf.targets)
    isempty(dbf.input_transforms) || (d["input_transforms"] = dbf.input_transforms)
    isempty(dbf.target_transforms) || (d["target_transforms"] = dbf.target_transforms)
    dbf.loader isa RowLoader || (d["loader"] = get_metadata(dbf.loader))
    return d
end

struct Processor{N, D}
    data::FunneledData{DBFunnel, N}
    device::D
    id::String
end

# `list` is the funnel's list the columns belong to, so a refusal can name the entry at fault.
function transform!(
        arr::AbstractArray{T, N}, vars::AbstractVector, unique_values::AbstractDict, list::AbstractString
    ) where {T <: Number, N}

    # TODO: avoid having to check `haskey` several times
    idxs = column_indices(Iterators.map(colname, vars), unique_values)
    for (I, var) in zip(idxs, vars)
        if haskey(unique_values, colname(var))
            if var.transform !== identity
                throw(
                    TransformError(
                        "`$(colname(var))` is one-hot encoded and cannot be transformed",
                        [transform_field(list), colname(var)]
                    )
                )
            end
        else
            idx = only(I)
            slice = selectdim(arr, N - 1, idx)
            copy!(slice, var.transform(slice))
        end
    end
    return arr
end

function encode_transform(cols, vars::AbstractVector, unique_values::AbstractDict, list::AbstractString)
    arr = encode_columns(cols, Iterators.map(colname, vars), unique_values)
    transform!(arr, vars, unique_values, list)
    return arr
end

# TODO: also create tensor of paths if any of `input_paths` or `target_paths` is not `nothing`
function (p::Processor)(cols)
    (; funnel, require_targets, unique_values) = p.data
    input::Array{Float32, 2} = encode_transform(cols, get_inputs(funnel), unique_values, "inputs")
    target::Maybe{Array{Float32, 2}} = if require_targets
        encode_transform(cols, get_targets(funnel), unique_values, "targets")
    else
        nothing
    end
    _id::Vector{Int64} = Tables.getcolumn(cols, Symbol(p.id))
    return (; _id, input = p.device(input), target = p.device(target))
end

function get_templates(data::FunneledData{DBFunnel})
    (; funnel, unique_values) = data
    input_names, target_names = funnel.inputs, funnel.targets
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
        suffix::Union{AbstractString, AbstractVector, Tuple}, destination::AbstractString
    )

    # One suffix per selected field: each is written as its own set of columns, `target_suffix`.
    suffixes = suffix isa AbstractString ? [suffix] : collect(suffix)
    length(suffixes) == length(select) ||
        throw(ArgumentError("There should be as many suffixes as selected fields"))
    allunique(suffixes) || throw(ArgumentError("Each selected field needs a distinct suffix"))

    targets = colname.(get_targets(data.funnel))
    output_names::Vector{String} = String[join((tgt, s), "_") for s in suffixes for tgt in targets]
    output_types::Vector{Type} = Type[column_type(tgt, data.unique_values) for _ in suffixes for tgt in targets]
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
            columns = reduce(
                vcat,
                (decode_columns(collect(batch[field]), targets, data.unique_values) for field in select)
            )
            append_batch(appender, batch._id, columns)
        end
    end

    return output_names
end
