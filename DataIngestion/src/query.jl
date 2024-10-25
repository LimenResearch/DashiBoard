struct Query
    node::SQLNode
    params::Dict{String, Any}
end

Query(node::SQLNode) = Query(node, Dict{String, Any}())

get_node(q::Query) = q.node
get_params(q::Query) = q.params

function parametric_render(catalog::SQLCatalog, query::Query)
    sql = render(catalog, get_node(query))
    params = pack(sql, get_params(query))
    return sql, params
end

function chain(queries)
    node = mapfoldl(get_node, |>, queries)
    params = mapfoldl(get_params, merge!, queries, init = Dict{String, Any}())
    return Query(node, params)
end

function DBInterface.execute(f::Base.Callable, repo::Repository, query::Query)
    sql, params = parametric_render(get_catalog(repo), query)
    return DBInterface.execute(f, repo, String(sql), params)
end

function DBInterface.execute(f::Base.Callable, repo::Repository, query::SQLNode, params = Dict{String, Any}())
    return DBInterface.execute(f, repo, Query(query, params))
end
