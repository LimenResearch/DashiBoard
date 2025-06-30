function digraph(nodes::AbstractVector{Node})
    Base.require_one_based_indexing(nodes)
    N = length(nodes)
    edges, vars, targets = Edge{Int}[], String[], Dict{String, Vector{Int}}()
    for (i, node) in pairs(nodes)
        for var in get_outputs(node)
            push!(vars, var)
            push!(edges, Edge(i, N + length(vars)))
        end
        for var in get_inputs(node)
            tgts = get!(targets, var, Int[])
            push!(tgts, i)
        end
    end
    allunique(vars) || throw(ArgumentError("Overlapping outputs"))
    for (idx, var) in pairs(vars)
        for tgt in get(targets, var, Int[])
            push!(edges, Edge(N + idx, tgt))
        end
    end
    return DiGraph(edges)
end

compute_height(nodes::AbstractVector) = compute_height(digraph(nodes), get_update.(nodes))

function compute_height(g::DiGraph, us::AbstractVector{Bool})
    hs = similar(Vector{Int}, nv(g))
    N = length(us)
    for i in topological_sort(g)
        nb = inneighbors(g, i)
        h = maximum(view(hs, nb), init = -1)
        # for output vars, simply stick with the maximum height of the inputs
        u = i ≤ N && (us[i] || h ≥ 0)
        hs[i] = h + u
    end
    return hs[1:N]
end

function layers(hs::AbstractVector{<:Integer})
    P = sortperm(hs)
    starts = findall(>(0), diff([-1; hs[P]]))
    stops = [starts .- 1; length(P)][2:end]
    return Iterators.map(Fix1(view, P) ∘ range, starts, stops)
end
