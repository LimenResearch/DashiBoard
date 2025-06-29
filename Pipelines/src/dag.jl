is_input_of(src::Node, tgt::Node) = !isdisjoint(src.outputs, tgt.inputs)

function adjacency_matrix(nodes::AbstractVector{Node})
    N = length(nodes)
    M = spzeros(Bool, N, N)
    M .= is_input_of.(nodes, permutedims(nodes))
    return M
end

digraph(nodes::AbstractVector{Node}) = DiGraph(adjacency_matrix(nodes))

compute_height(nodes::AbstractVector) = compute_height(digraph(nodes), get_update.(nodes))

function compute_height(g::DiGraph, us::AbstractVector{Bool})
    hs = similar(Vector{Int}, nv(g))
    for i in topological_sort(g)
        nb = inneighbors(g, i)
        h = maximum(view(hs, nb), init = -1)
        u = us[i] || h ≥ 0
        hs[i] = h + u
    end
    return hs
end

function layers(hs::AbstractVector{<:Integer}, P::AbstractVector{<:Integer} = sortperm(hs))
    cs, n = fill(0, hs[last(P)] + 1), 0
    for h in hs
        h ≥ 0 ? (cs[h + 1] += 1) : (n += 1)
    end
    scs = accumulate(+, cs, init = n + firstindex(P) - 1)
    return (view(P, (s - c + 1):s) for (c, s) in zip(cs, scs))
end
