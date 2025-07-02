struct SortedEdges{S, D}
    src::S
    dst::D
    rgs::Vector{UnitRange{Int}} 
end

# TODO: make lazy?
(s::SortedEdges)((i, rg)::Pair) = s.src[i] => s.dst[rg]
to_edges((src, dsts)::Pair) = Edge{Int}.(src, dsts)

iterate_pairs(s::SortedEdges) = Iterators.map(s, pairs(s.rgs))
iterate_edges(s::SortedEdges) = Iterators.flatmap(to_edges, iterate_pairs(s))

function sorted_edges(nodes::AbstractVector{Node}, input_names::AbstractVector)
    Base.require_one_based_indexing(nodes)

    not_in_source = ∉(Set{String}(input_names))
    vars = mapfoldl(get_outputs, append!, nodes, init = String[])

    inputs, indices = String[], Int[]
    for (i, node) in enumerate(nodes)
        append!(inputs, Iterators.filter(not_in_source, get_inputs(node)))
        append!(indices, fill(i, length(inputs) - length(indices)))
    end

    # Validation

    if inputs ⊈ vars
        notfound = setdiff(vars, inputs)
        throw(ArgumentError("Input vars $(notfound) not found in data or card outputs"))
    end
    if !isdisjoint(vars, input_names)
        overwrite = vars ∩ input_names
        throw(ArgumentError("Output vars $(overwrite) are present in the data"))
    end
    if !allunique(vars)
        overlapping = repeated_values(vars)
        throw(ArgumentError("Overlapping outputs $(overlapping)"))
    end

    # Compute output

    perm, b, e = boundaries(inputs)
    starts, stops = findall(b), findall(e)
    rgs = range.(starts, stops)

    N = length(nodes)
    d = Dict{String, Int}(Iterators.map(reverse, pairs(vars)))
    outputs = SortedEdges(keys(nodes), keys(vars) .+ N, get_ranges(@. length(get_outputs(nodes))))
    targets = SortedEdges([d[inputs[perm[i]]] + N for i in starts], indices[perm], rgs)

    return outputs, targets, vars
end

function digraph(nodes::AbstractVector{Node}, ns::AbstractVector)
    outputs, targets, _ = sorted_edges(nodes, ns)
    edges = mapfoldl(iterate_edges, append!, (outputs, targets), init = Edge{Int}[])
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
    P, b, e = boundaries(hs)
    starts, stops = findall(@. b && hs ≥ 0), findall(@. e && hs ≥ 0)
    return Iterators.map(Fix1(view, P) ∘ range, starts, stops)
end

function graphviz(io::IO, nodes::AbstractVector{Node}, ns::AbstractVector)
    outputs, targets, vars = sorted_edges(nodes, ns)
    N = length(nodes)

    println(io, "digraph G{")
    println(io, "  bgcolor = \"transparent\";")
    println(io, "  node [fillcolor = \"transparent\"];")
    println(io)

    println(io, "  subgraph cards {")
    println(io, "    node [shape = \"box\"];")
    for (i, node) in enumerate(nodes)
        name = card_name(get_card(node))
        l = get_update(node) ? string(name, " ", "⬤") : name
        println(io, "    $(i) [label = \"$(l)\"];")
    end
    println(io, "  }")
    println(io)

    println(io, "  subgraph vars {")
    println(io, "    node [shape = \"none\"];")
    for (j, var) in enumerate(vars)
        println(io, "    $(N + j) [label = \"$(var)\"];")
    end
    println(io, "  }")
    println(io)

    println(io, "  edge [arrowhead = \"none\"]")
    for (src, dsts) in iterate_pairs(outputs)
        print(io, "  ", src, " -> {")
        join(io, dsts, " ")
        println(io, "};")
    end
    println(io)

    println(io, "  edge [arrowhead = \"normal\"]")
    for (src, dsts) in iterate_pairs(targets)
        print(io, "  ", src, " -> {")
        join(io, dsts, " ")
        println(io, "};")
    end

    return println(io, "}")
end
