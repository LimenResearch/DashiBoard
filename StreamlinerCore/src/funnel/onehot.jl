function column_number(k::AbstractString, unique_values::AbstractDict)
    vals = get(unique_values, k, nothing)
    return isnothing(vals) ? 1 : length(vals)
end

function column_indices(ks, unique_values::AbstractDict)
    ns = map(Fix2(column_number, unique_values), ks)
    cns = cumsum(ns)
    return @. range(cns - ns + 1, cns)
end

function encode_column(cols, k::AbstractString, unique_values::AbstractDict)::Matrix{Float32}
    v = Tables.getcolumn(cols, Symbol(k))
    vals = get(unique_values, k, nothing)
    # TODO: better error handling here
    return isnothing(vals) ? v' : Flux.onehotbatch(v, vals)
end

function encode_columns(cols, ks, unique_values::AbstractDict)
    ms = [encode_column(cols, k, unique_values)::AbstractMatrix for k in ks]
    return reduce(vcat, ms)
end

function decode_columns(mat, ks, unique_values::AbstractDict)
    rgs = column_indices(ks, unique_values)
    return map(ks, rgs) do k, rg
        vals = get(unique_values, k, nothing)
        if isnothing(vals)
            mat[only(rg), :]
        else
            m = mat[rg, :]
            I = argmax(m, dims = 1)
            is = getindex.(I, 1)
            vals[is]
        end
    end
end

function column_type(k::AbstractString, unique_values::AbstractDict)
    vals = get(unique_values, k, nothing)
    return isnothing(vals) ? Float32 : eltype(vals)
end

function compute_unique_values(data::FunneledData)
    (; table_spec, funnel, partition) = data
    (; repository, table, schema) = table_spec
    inputs, constant_inputs = get_inputs(funnel), get_constant_inputs(funnel)
    targets, constant_targets = get_targets(funnel), get_constant_targets(funnel)
    input_names, target_names = colname.(inputs), colname.(targets)

    unique_values = Dict{String, AbstractVector}()
    src = From(table) |> filter_partition(partition)
    schm = DBInterface.execute(Tables.schema, repository, src |> Limit(0); schema)
    cols = union(input_names, constant_inputs, target_names, constant_targets)
    idxs = indexin(Symbol.(cols), collect(schm.names))

    for (i, k) in zip(idxs, cols)
        T = schm.types[i]
        if !(nonmissingtype(T) <: Number) # TODO: what to do with booleans?
            q = src |> Group(Get(k)) |> Select(Get(k)) |> Order(Get(k))
            v = DBInterface.execute(Fix1(map, first), repository, q; schema)
            unique_values[k] = v
        end
    end

    return unique_values
end

function compute_unique_values!(data::FunneledData)
    data.unique_values = compute_unique_values(data)
    return data
end
