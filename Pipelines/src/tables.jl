# This simple table type is the preferred way to store tables in memory
const SimpleTable = OrderedDict{String, AbstractVector}

function fromtable(data)
    cols = Tables.columns(data)
    colnames = Tables.columnnames(cols)
    return SimpleTable(String(k) => Tables.getcolumn(cols, k) for k in colnames)
end

join_names(args...) = join(args, '_')

function new_name(c::AbstractString, cols::AbstractVector{<:AbstractString})
    for i in Iterators.countfrom()
        c′ = join_names(c, i)
        c′ in cols || return c′
    end
end
