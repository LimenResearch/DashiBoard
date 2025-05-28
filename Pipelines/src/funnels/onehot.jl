function column_length(k::AbstractString, uvals::AbstractDict)
    vals = get(uvals, k, nothing)
    return isnothing(vals) ? 1 : length(vals)
end

function column_indices(ks::AbstractVector, uvals::AbstractDict)
    ns = map(Fix2(column_length, uvals), ks)
    cns = cumsum(ns)
    return @. range(cns - ns + 1, cns)
end

function encode_column(cols, k::AbstractString, uvals::AbstractDict)::Matrix{Float32}
    v = Tables.getcolumn(cols, Symbol(k))
    vals = get(uvals, k, nothing)
    # TODO: better error handling here
    return isnothing(vals) ? v' : isequal.(vals, permutedims(v))
end

function encode_columns(cols, ks::AbstractVector, uvals::AbstractDict)
    ms = [encode_column(cols, k, uvals) for k in ks]
    return reduce(vcat, ms)
end

function decode_columns(mat, ks::AbstractVector, uvals::AbstractDict)
    rgs = column_indices(ks, uvals)
    return map(ks, rgs) do k, rg
        vals = get(uvals, k, nothing)
        return if isnothing(vals)
            mat[only(rg), :]
        else
            m = mat[rg, :]
            I = argmax(m, dims = 1)
            is = getindex.(I, 1)
            return uvals[is]
        end
    end
end
