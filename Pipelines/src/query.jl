struct Query
    table::String
    filters::Filters
end

function print_query(io::IO, query::Query)
    print(io, "FROM ", query.table, "\n")
    params = print_filters(io, query.filters)
    return params
end
