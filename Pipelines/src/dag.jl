repeated_keys(cs) = Iterators.flatmap(splat(Iterators.repeated), pairs(cs))
lazy_pairs(cs, xs) = Iterators.map(=>, repeated_keys(cs), xs)

function digraph(nodes::AbstractVector{Node}, colnames::AbstractVector)
    Base.require_one_based_indexing(nodes)
    dict = Dict{String, Int}(colnames .=> 0)

    output_vars = Iterators.flatmap(get_outputs, nodes)
    repeated = unique(var for (i, var) in enumerate(output_vars) if i ≠ get!(dict, var, i))

    # Validation

    if !isempty(repeated)
        throw(ArgumentError("Output vars $(repeated) would be overwritten"))
    end

    return digraph(nodes, dict)
end

function digraph(nodes::AbstractVector{Node}, dict::AbstractDict)

    # compute number of nodes and output variables

    output_counts = length.(get_outputs.(nodes))
    N, n_outputs = length(nodes), sum(output_counts, init = 0)
    outputs = 1:n_outputs

    # preprocess inbound edges

    inputs, input_counts, counts = Int[], fill(0, N), fill(0, n_outputs + 1)
    for (i, node) in pairs(nodes), input_var in get_inputs(node)
        input = dict[input_var]
        if input > 0
            push!(inputs, input)
            input_counts[i] += 1
            counts[input + 1] += 1
        end
    end
    for i in 1:n_outputs
        counts[i + 1] += counts[i]
    end
    n_inputs = sum(input_counts, init = 0)

    # initialize and fill `edges` array

    edges = fill(Edge(0, 0), n_outputs + n_inputs)
    for (node_idx, output) in lazy_pairs(output_counts, outputs)
        edge_idx = output
        edges[edge_idx] = Edge(node_idx, N + output)
    end
    for (node_idx, input) in lazy_pairs(input_counts, inputs)
        edge_idx = n_outputs + (counts[input] += 1)
        edges[edge_idx] = Edge(N + input, node_idx)
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
