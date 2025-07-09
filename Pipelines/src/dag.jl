to_edges(fadj, N::Integer) = [Edge(N + idx, i) for (idx, is) in enumerate(fadj) for i in is]

function digraph(nodes::AbstractVector{Node}, colnames::AbstractVector)
    Base.require_one_based_indexing(nodes)

    dict = Dict{String, Int}(colnames .=> 0)
    outputs = Iterators.flatmap(get_outputs, nodes)
    overwritten = unique(var for (i, var) in enumerate(outputs) if i ≠ get!(dict, var, i))

    # Validation

    if !isempty(overwritten)
        throw(ArgumentError("Output vars $(overwritten) would be overwritten"))
    end

    # Generate edges

    N = length(nodes)
    srcs = reduce(vcat, StepRangeLen.(1:N, 0, length.(get_outputs.(nodes))))
    nvars = length(srcs)
    dsts = (N + 1):(N + nvars)

    targets = [Int[] for _ in 1:nvars]
    for (i, n) in pairs(nodes), var in get_inputs(n)
        idx = dict[var]
        (idx > 0) && push!(targets[idx], i)
    end

    edges::Vector{Edge{Int}} = vcat(Edge.(srcs, dsts), to_edges(targets, N))

    # Build graph

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

function layers(hs::AbstractVector)
    m = maximum(hs, init = -1)
    ls = Vector{Int}[Int[] for _ in 0:m]
    for (i, h) in pairs(hs)
        (h ≥ 0) && push!(ls[h + 1], i)
    end
    return ls
end

function graphviz(io::IO, nodes::AbstractVector{Node}, colnames::AbstractVector)
    g = digraph(nodes, colnames)
    N = length(nodes)
    vars = Iterators.flatmap(get_outputs, nodes)

    println(io, "digraph G{")
    println(io, "  bgcolor = \"transparent\";", "\n")

    println(io, "  subgraph cards {")
    println(io, "    node [shape = \"box\" style = \"filled\" color = \"transparent\"];")
    for (i, node) in enumerate(nodes)
        name = card_name(get_card(node))
        fillcolor = get_update(node) ? "white" : "transparent"
        println(io, "    \"$(i)\" [label = \"$(name)\" fillcolor = \"$(fillcolor)\"];")
    end
    println(io, "  }", "\n")

    println(io, "  subgraph vars {")
    println(io, "    node [shape = \"none\"];")
    for (j, var) in enumerate(vars)
        println(io, "    \"$(N + j)\" [label = \"$(var)\"];")
    end
    println(io, "  }")

    for src in 1:nv(g)
        (src == 1) && println(io, "\n", "  edge [arrowhead = \"none\"];")
        (src == N + 1) && println(io, "\n", "  edge [arrowhead = \"normal\"];")
        outs = outneighbors(g, src)
        isempty(outs) && continue
        print(io, "  ", "\"", src, "\"", " -> {\"")
        join(io, outs, "\" \"")
        println(io, "\"};")
    end

    return println(io, "}")
end
