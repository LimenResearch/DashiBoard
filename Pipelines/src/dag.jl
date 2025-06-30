function digraph(nodes::AbstractVector{Node}, ns::AbstractVector)
    Base.require_one_based_indexing(nodes)

    N = length(nodes)
    input_names = Set{String}(ns)
    edges, output_vars, targets = Edge{Int}[], String[], Dict{String, Vector{Int}}()

    for (i, node) in pairs(nodes)
        for output_var in get_outputs(node)
            push!(output_vars, output_var)
            push!(edges, Edge(i, N + length(output_vars)))
        end
        for input_var in get_inputs(node)
            input_var in input_names && continue
            tgts = get!(targets, input_var, Int[])
            push!(tgts, i)
        end
    end

    for (idx, var) in pairs(output_vars)
        for tgt in get(targets, var, Int[])
            push!(edges, Edge(N + idx, tgt))
        end
    end

    # Validation
    input_vars = keys(targets)
    diff = setdiff(input_vars, output_vars)
    overwrite = output_vars ∩ input_names
    allunique(output_vars) || throw(ArgumentError("Overlapping outputs"))
    isempty(diff) || throw(ArgumentError("Vars $(collect(diff)) not found in data or card outputs"))
    isempty(overwrite) || throw(ArgumentError("Output vars $(overwrite) are present in the data"))

    return DiGraph(edges)
end

function compute_height(nodes::AbstractVector, ns::AbstractVector)
    g::DiGraph, us::BitVector = digraph(nodes, ns), get_update.(nodes)
    return compute_height(g, us)
end

function compute_height(g::DiGraph, us::BitVector)
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
