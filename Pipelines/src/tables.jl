# This simple table type is the preferred way to store tables in memory
const SimpleTable = OrderedDict{String, AbstractVector}

function fromtable(data)
    cols = Tables.columns(data)
    tbl = SimpleTable()
    for k in Tables.columnnames(cols)
        tbl[String(k)] = Tables.getcolumn(cols, k)
    end
    return tbl
end

join_names(args...) = join(args, "_")

function new_name(c::AbstractString, cols::AbstractVector{<:AbstractString})
    for i in Iterators.countfrom()
        c′ = join_names(c, i)
        c′ in cols || return c′
    end
end
