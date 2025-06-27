is_input_of(src::Node, tgt::Node) = !isdisjoint(src.outputs, tgt.inputs)

function adjacency_matrix(nodes::AbstractVector{Node})
    N = length(nodes)
    M = spzeros(Bool, N, N)
    M .= is_input_of.(nodes, permutedims(nodes))
    return M
end

digraph(nodes::AbstractVector{Node}) = DiGraph(adjacency_matrix(nodes))

function group_rank(rank::AbstractVector{<:Integer})
    m = maximum(rank)
    d = [Int[] for _ in 1:m]
    for (i, rk) in pairs(rank)
        (rk > 0) && push!(d[rk], i)
    end
    return d
end

compute_rank(nodes::AbstractVector) = compute_rank(digraph(nodes), get_update.(nodes))

function compute_rank(g::DiGraph, update::AbstractVector{Bool})
    rank = collect(Int, update)

    for i in topological_sort(g)
        nb = inneighbors(g, i)
        rk = maximum(view(rank, nb), init = 0)
        (rk > 0) && (rank[i] = rk + 1)
    end

    return rank
end
