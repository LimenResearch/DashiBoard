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

function join_on_row_number(tbl, id_var, sel)
    cond = Agg.row_number() .== Get(id_var, over = Get(tbl))
    return LeftJoin(tbl => From(tbl), on = cond) |>
        Define(args = sel .=> Get.(sel, over = Get(tbl)))
end

# note: with empty partition, DuckDB preserves order
function join_on_row_number(tbl, tbls, id_vars, sels)
    init = From(tbl) |> Partition()
    return mapfoldl(splat(join_on_row_number), |>, zip(tbls, id_vars, sels); init)
end
