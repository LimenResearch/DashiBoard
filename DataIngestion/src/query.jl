struct ParametricNode
    node::SQLNode
    params::Dict{String, Any}
end

ParametricNode(node::SQLNode) = ParametricNode(node, Dict{String, Any}())

get_node(n::ParametricNode) = n.node
get_params(n::ParametricNode) = n.params

struct Query
    nodes::Vector{ParametricNode}
end

Query(node::ParametricNode) = Query([node])
Query(node::SQLNode) = Query(ParametricNode(node))

get_nodes(q::Query) = q.nodes

Base.:|>(q1::Query, q2::Query) = Query(vcat(get_nodes(q1), get_nodes(q2)))

chain(queries::AbstractVector{Query}) = Query(reduce(vcat, get_nodes.(queries)))

function ParametricNode(query::Query)
    node = mapfoldl(get_node, |>, query.nodes)
    params = mapfoldl(get_params, merge!, query.nodes, init = Dict{String, Any}())
    return ParametricNode(node, params)
end

function DBInterface.execute(f::Base.Callable, repo::Repository, query::Query)
    return DBInterface.execute(f, repo, ParametricNode(query))
end

function DBInterface.execute(f::Base.Callable, repo::Repository, node::SQLNode, params = Dict{String, Any}())
    return DBInterface.execute(f, repo, ParametricNode(node, params))
end

function DBInterface.execute(f::Base.Callable, repo::Repository, n::ParametricNode)
    node, params = get_node(n), get_params(n)
    sql = render(get_catalog(repo), node)
    return DBInterface.execute(f, repo, String(sql), pack(sql, params))
end
