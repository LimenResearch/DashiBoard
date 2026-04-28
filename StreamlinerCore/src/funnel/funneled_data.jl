abstract type Funnel end

struct FunneledData{F <: Funnel, N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    id_var::String # TODO: determine if this belong here?
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
        id_var::AbstractString,
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
        id_var::AbstractString = fd.id_var,
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
    inputs, constant_inputs = get_inputs(funnel), get_constant_inputs(funnel)
    targets, constant_targets = get_targets(funnel), get_constant_targets(funnel)
    input_names, target_names = colname.(inputs), colname.(targets)

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
