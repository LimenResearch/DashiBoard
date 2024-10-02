struct Query
    table::String
    filters::Filters
end

function print_query(io::IO, query::Query)
    print(io, "FROM ", query.table, "\n")
    params = print_filters(io, query.filters)
    return params
end

function DBInterface.execute(f::Base.Callable, ex::Experiment, query::Query)
    io = IOBuffer()
    params = print_query(io, query)
    sql = String(take!(io))
    return DBInterface.execute(f, ex.repository, sql, params)
end
