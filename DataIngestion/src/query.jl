struct Query
    table::String
    filters::Filters
    select::Vector{String}
end

function Clause(q::Query)
    clause = Clause(From(q.table))
    for (i, f) in enumerate(q.filters.intervals)
        prefix = string("interval", i)
        clause *= Clause(f, prefix)
    end
    for (i, f) in enumerate(q.filters.lists)
        prefix = string("list", i)
        clause *= Clause(f, prefix)
    end
    clause *= Clause(Select(args = [Get[colname] for colname in q.select]))

    return clause
end
