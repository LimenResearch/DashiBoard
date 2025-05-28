function assert_columnaccess(cols)
    if !Tables.columnaccess(cols)
        throw(ArgumentError("Only column-based tables are accepted."))
    end
    return true
end

"""
    _numobs(cols)

Compute the number of rows of a column-based table `cols`.
"""
function _numobs(cols)
    assert_columnaccess(cols)
    ns = Tables.columnnames(cols)
    return isempty(ns) ? 0 : length(Tables.getcolumn(cols, first(ns)))
end

"""
    _init(schm::Tables.Schema)

Initialize an empty table with schema `schm`.
"""
function _init(schm::Tables.Schema)
    return OrderedDict{Symbol, Vector}(n => T[] for (n, T) in zip(schm.names, schm.types))
end

"""
    _append!(batch::AbstractDict, cols, rg = Colon())

Append rows `rg` of column-based table `cols` to the dict table `batch`.
"""
function _append!(batch::AbstractDict, cols, rg = Colon())
    assert_columnaccess(cols)
    for (k, v) in pairs(batch)
        col = Tables.getcolumn(cols, k)
        append!(v, view(col, rg))
    end
    return batch
end

# Stream DuckDB data

struct Batches{T, names, types}
    chunks::T
    schema::Tables.Schema{names, types}
    batchsize::Int
    nrows::Int

    function Batches(
            chunks::T,
            schema::Tables.Schema{names, types},
            batchsize::Integer,
            nrows::Integer
        ) where {T, names, types}

        return new{T, names, types}(chunks, schema, batchsize, nrows)
    end
end

"""
    Batches(tbl, batchsize::Integer, nrows::Integer)

Construct a `Batches` iterator based on a table `tbl` with `nrows` in total.
The resulting object iterates column-based tables with `batchsize` rows each.
"""
function Batches(tbl, batchsize::Integer, nrows::Integer)
    chunks, schema = Tables.partitions(tbl), Tables.schema(tbl)
    return Batches(chunks, schema, batchsize, nrows)
end

function Base.eltype(::Type{Batches{T}}) where {T}
    return OrderedDict{Symbol, Vector}
end

Base.length(r::Batches) = cld(r.nrows, r.batchsize)

Base.size(r::Batches) = (length(r),)

function Base.iterate(r::Batches, (res, j) = (iterate(r.chunks), 0))
    isnothing(res) && return nothing
    chunk, st = res
    batch = _init(r.schema)
    cols = Tables.columns(chunk)
    while _numobs(batch) < r.batchsize
        if _numobs(cols) ≤ j
            res, j = iterate(r.chunks, st), 0
            isnothing(res) && break
            chunk, st = res
            cols = Tables.columns(chunk)
        end
        j′ = min(_numobs(cols), j + r.batchsize - _numobs(batch))
        _append!(batch, cols, (j + 1):j′)
        j = j′
    end
    return _numobs(batch) == 0 ? nothing : (batch, (res, j))
end
