function digraph(nodes::AbstractVector{Node}, colnames::AbstractVector)
    Base.require_one_based_indexing(nodes)
    dict = Dict{String, Int}(colnames .=> 0)

    outputs = Iterators.flatmap(get_outputs, nodes)
    overwritten = unique(var for (i, var) in enumerate(outputs) if i ≠ get!(dict, var, i))

    # Validation

    if !isempty(overwritten)
        throw(ArgumentError("Output vars $(overwritten) would be overwritten"))
    end

    return digraph(nodes, dict)
end

function digraph(nodes::AbstractVector{Node}, dict::AbstractDict)

    # first collect srcs and dsts of edges from vars to nodes

    input_vars, target_nodes = Int[], Int[]
    for (i, n) in pairs(nodes), var in get_inputs(n)
        idx = dict[var]
        (idx > 0) && (push!(input_vars, idx); push!(target_nodes, i))
    end

    # initialize edges and add edges from nodes to vars (they come presorted)

    lens = length.(get_outputs.(nodes))
    n_nodes, n_outputs, n_inputs = length(nodes), sum(lens), length(input_vars)
    edges = fill(Edge(0, 0), n_outputs + n_inputs)

    counter = 0
    for (i, len) in pairs(lens)
        rg = range(counter + 1, counter + len)
        edges[rg] .= Edge.(i, n_nodes .+ rg)
        counter += len
    end

    # then, add edges from vars to nodes (count-sort on the fly)

    counts = fill(0, n_outputs + 1)
    for idx in input_vars
        counts[idx + 1] += 1
    end
    for idx in 1:n_outputs
        counts[idx + 1] += counts[idx]
    end

    for (input_var, target_node) in zip(input_vars, target_nodes)
        index = counts[input_var] += 1
        edges[n_outputs + index] = Edge(n_nodes + input_var, target_node)
    end

    return DiGraph(edges)
end

function compute_height(g::DiGraph, nodes::AbstractVector{Node})
    us::BitVector = get_update.(nodes)
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

# TODO: make look customizable (esp., match font with AlgebraOfGraphics)
function graphviz(io::IO, g::DiGraph, nodes::AbstractVector{Node})
    N = length(nodes)
    vars = Iterators.flatmap(get_outputs, nodes)

    println(io, "digraph G{")
    println(io, "  bgcolor = \"transparent\";", "\n")

    println(io, "  subgraph cards {")
    println(io, "    node [shape = \"box\" style = \"filled\"];")
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
