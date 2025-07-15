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

function new_name(c::AbstractString, cols...)
    used_names = union!(Set{String}(), cols...)
    candidates = Iterators.map(Fix1(join_names, c), Iterators.countfrom(1))
    return first(Iterators.dropwhile(in(used_names), candidates))
end

# note: with empty partition, DuckDB preserves order
function with_id(table::AbstractString, id_var)
    return From(table) |>
        Partition() |>
        Define(id_var => Agg.row_number())
end

function join_on_row_number(tbl_name, id_var)
    return LeftJoin(
        tbl_name => From(tbl_name),
        on = Agg.row_number() .== Get(id_var, over = Get(tbl_name))
    )
end
