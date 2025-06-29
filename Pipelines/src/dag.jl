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

function layers(hs::AbstractVector{<:Integer})
    Base.require_one_based_indexing(hs)
    P = sortperm(hs)
    starts = findall(>(0), diff([-1; hs[P]]))
    stops = [starts .- 1; length(P)][2:end]
    return Iterators.map(Fix1(view, P) ∘ range, starts, stops)
end
