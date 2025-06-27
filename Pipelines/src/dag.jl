is_input_of(src::Node, tgt::Node) = !isdisjoint(src.outputs, tgt.inputs)

function adjacency_matrix(nodes::AbstractVector{Node})
    N = length(nodes)
    M = spzeros(Bool, N, N)
    M .= is_input_of.(nodes, permutedims(nodes))
    return M
end

digraph(nodes::AbstractVector{Node}) = DiGraph(adjacency_matrix(nodes))

function group_height(hs::AbstractVector{<:Integer})
    m = maximum(hs)
    d = [Int[] for _ in 0:m]
    for (i, h) in pairs(hs)
        h ≥ 0 && push!(d[h + 1], i)
    end
    return d
end

compute_height(nodes::AbstractVector) = compute_height(digraph(nodes), get_update.(nodes))

compute_height(g::DiGraph, us::AbstractVector{Bool}) = compute_height!(similar(us, Int), g, us)

function compute_height!(hs::AbstractVector{Int}, g::DiGraph, us::AbstractVector{Bool})
    for i in topological_sort(g)
        nb = inneighbors(g, i)
        h = maximum(view(hs, nb), init = -1)
        u = us[i] || h ≥ 0
        hs[i] = h + u
    end
    return hs
end
