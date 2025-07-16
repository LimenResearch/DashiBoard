function column_number(k::AbstractString, uvals::AbstractDict)
    vals = get(uvals, k, nothing)
    return isnothing(vals) ? 1 : length(vals)
end

function column_indices(ks::AbstractVector, uvals::AbstractDict)
    ns = map(Fix2(column_number, uvals), ks)
    cns = cumsum(ns)
    return @. range(cns - ns + 1, cns)
end

function encode_column(cols, k::AbstractString, uvals::AbstractDict)::Matrix{Float32}
    v = Tables.getcolumn(cols, Symbol(k))
    vals = get(uvals, k, nothing)
    # TODO: better error handling here
    return isnothing(vals) ? v' : onehotbatch(v, vals)
end

function encode_columns(cols, ks::AbstractVector, uvals::AbstractDict)
    ms = [encode_column(cols, k, uvals) for k in ks]
    return reduce(vcat, ms)
end

function decode_columns(mat, ks::AbstractVector, uvals::AbstractDict)
    rgs = column_indices(ks, uvals)
    return map(ks, rgs) do k, rg
        vals = get(uvals, k, nothing)
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

function column_type(k::AbstractString, uvals::AbstractDict)
    vals = get(uvals, k, nothing)
    return isnothing(vals) ? Float32 : eltype(vals)
end
