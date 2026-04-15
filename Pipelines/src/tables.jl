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

function join_on_row_number(
        from::SQLNode, t::AbstractString,
        id_var::AbstractString, sel::AbstractVector
    )
    return from |>
        Partition() |>
        LeftJoin(t => From(t), on = Agg.row_number() .== Get(id_var, over = Get(t))) |>
        Define(args = sel .=> Get.(sel, over = Get(t))) |>
        Order(Agg.row_number())
end

function join_on_row_number(
        orig::AbstractString, t::AbstractString,
        id_var::AbstractString, sel::AbstractVector
    )
    return join_on_row_number(From(orig), t, id_var, sel)
end
