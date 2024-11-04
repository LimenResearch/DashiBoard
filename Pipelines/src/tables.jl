# This simple table type is the preferred way to store tables in memory
const SimpleTable = OrderedDict{String, AbstractVector}

function fromtable(data)
    cols = Tables.columns(data)
    return SimpleTable(String(k) => Tables.getcolumn(cols, k) for k in cols)
end

mapcols!(f, s::SimpleTable) = (map!(f, values(s)); s)

function mergedisjointcols!(s::SimpleTable, t::SimpleTable)
    if isdisjoint(keys(s), keys(t))
        return merge!(s, t)
    else
        sharedkeys = intersect(keys(s), keys(t))
        throw(
            ArgumentError(
                """
                Overwriting table is not allowed, the following column names are repeated:
                $sharedkeys
                """
            )
        )
    end
end
