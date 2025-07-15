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
function join_on_row_number(tbl1, tbl2, id_var, sel)
    cond = Agg.row_number() .== Get(id_var, over = Get(tbl2))
    return From(tbl1) |>
        Partition() |>
        LeftJoin(tbl2 => From(tbl2), on = cond) |>
        Define(args = sel .=> Get.(sel, over = Get(tbl2)))
end
