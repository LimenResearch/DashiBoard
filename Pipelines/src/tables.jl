# This simple table type is the preferred way to store tables in memory
const SimpleTable = OrderedDict{String, AbstractVector}

function fromtable(data)
    cols = Tables.columns(data)
    tbl = SimpleTable()
    for k in Tables.columnnames(cols)
        tbl[string(k)] = Tables.getcolumn(cols, k)
    end
    return tbl
end

join_names(args...) = join(args, "_")

function new_name(c::AbstractString, cols)
    for i in Iterators.countfrom()
        c′ = join_names(c, i)
        c′ in cols || return c′
    end
    return
end

get_id_col(ns) = new_name("id", ns)

# note: with empty partition, DuckDB preserves order
function id_table(table::AbstractString, col)
    return From(table) |>
        Partition() |>
        Define(col => Agg.row_number())
end
