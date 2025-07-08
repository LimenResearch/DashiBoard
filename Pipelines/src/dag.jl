overwritten_keys(d::AbstractDict, ps) = unique(k for (k, v) in ps if !isequal(d[k], v))

function compute_dict(nodes::AbstractVector{Node}, colnames::AbstractVector)
    col_pairs = Iterators.zip(colnames, Iterators.repeated(0))
    out_pairs = Iterators.map(reverse, enumerate(Iterators.flatmap(get_outputs, nodes)))

    dict = merge(Dict{String, Int}(col_pairs), Dict{String, Int}(out_pairs))
    overwritten_cols = overwritten_keys(dict, col_pairs)
    overwritten_outs = overwritten_keys(dict, out_pairs)

    # Validation
    if !isempty(overwritten_cols)
        throw(ArgumentError("Output vars $(overwritten_cols) are present in the data"))
    end
    if !isempty(overwritten_outs)
        throw(ArgumentError("Overlapping outputs $(overwritten_outs)"))
    end

    return dict
end

function compute_edges(dict::AbstractDict, nodes::AbstractVector{Node})
    N = length(nodes)

    out_iter = enumerate(i for (i, n) in pairs(nodes) for _ in get_outputs(n))
    out_edges = [Edge(i, idx + N) for (idx, i) in out_iter]
    nouts = length(out_edges)

    in_iter = ((dict[v], i) for (i, n) in pairs(nodes) for v in get_inputs(n))
    in_edges = [Edge(idx + N, i) for (idx, i) in in_iter if idx > 0]
    nins = length(in_edges)

    edges = similar(Vector{Edge{Int}}, nouts + nins)
    copyto!(edges, out_edges)
    counting_sort!(edges, in_edges, by = src, skip = nouts)
    return edges
end

function digraph(nodes::AbstractVector{Node}, colnames::AbstractVector)
    Base.require_one_based_indexing(nodes)
    dict = compute_dict(nodes, colnames)
    edges = compute_edges(dict, nodes)
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
