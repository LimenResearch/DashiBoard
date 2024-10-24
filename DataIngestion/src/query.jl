struct Query
    node::SQLNode
    params::Dict{String, Any}
end

Query(node::SQLNode) = Query(node, Dict{String, Any}())

get_node(q::Query) = q.node
get_params(q::Query) = q.params

function chain(queries)
    node = mapfoldl(get_node, |>, queries)
    params = mapfoldl(get_params, merge!, queries, init = Dict{String, Any}())
    return Query(node, params)
end

function DBInterface.execute(f::Base.Callable, repo::Repository, query::Query)
    sql = render(get_catalog(repo), query.node)
    params = pack(sql, query.params)
    return DBInterface.execute(f, repo, String(sql), params)
end

function DBInterface.execute(f::Base.Callable, repo::Repository, query::SQLNode, params = Dict{String, Any}())
    return DBInterface.execute(f, repo, Query(query, params))
end
