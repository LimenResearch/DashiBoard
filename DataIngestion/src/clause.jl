struct Clause
    node::SQLNode
    params::Dict{String, Any}
end

Clause(node::SQLNode) = Clause(node, Dict{String, Any}())

Base.:*(c1::Clause, c2::Clause) = Clause(c1.node |> c2.node, merge(c1.params, c2.params))

function DBInterface.execute(f::Base.Callable, repo::Repository, clause::Clause)
    sql = render(get_catalog(repo), clause.node)
    params = pack(sql, clause.params)
    return DBInterface.execute(f, repo, String(sql), params)
end
