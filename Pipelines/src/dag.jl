function edges_metadata(nodes::AbstractVector{Node}, ns::AbstractVector)
    Base.require_one_based_indexing(nodes)

    input_names = Set{String}(ns)
    n_outputs = @. length(get_outputs(nodes))
    cn_outputs = cumsum(n_outputs)
    output_rgs = @. range(cn_outputs - n_outputs + 1, cn_outputs)
    output_vars = mapfoldl(get_outputs, append!, nodes, init = String[])

    targets = Dict{String, Vector{Int}}()
    for (i, node) in pairs(nodes)
        for input_var in Iterators.filter(∉(input_names), get_inputs(node))
            tgts = get!(targets, input_var, Int[])
            isnothing(tgts) || push!(tgts, i)
        end
    end

    # Validation
    if keys(targets) ⊈ output_vars
        notfound = setdiff(output_vars, keys(targets))
        throw(ArgumentError("Input vars $(notfound) not found in data or card outputs"))
    end
    if !isdisjoint(output_vars, input_names)
        overwrite = output_vars ∩ input_names
        throw(ArgumentError("Output vars $(overwrite) are present in the data"))
    end
    if !allunique(output_vars)
        overlapping = repeated_values(output_vars)
        throw(ArgumentError("Overlapping outputs $(overlapping)"))
    end

    return output_rgs, output_vars, targets
end

function digraph(nodes::AbstractVector{Node}, ns::AbstractVector)
    output_rgs, output_vars, targets = edges_metadata(nodes, ns)
    edges, N = Edge{Int}[], length(nodes)
    for (i, rg) in enumerate(output_rgs)
        append!(edges, Edge.(i, rg .+ N))
    end
    for (j, var) in enumerate(output_vars)
        tgts = get(targets, var, Int[])
        append!(edges, Edge.(N + j, tgts))
    end
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
    edges, output_vars = edges_metadata(nodes, ns)
    N = length(nodes)

    println(io, "digraph G{")
    println(io, "  subgraph {")
    println(io, "    node [shape = \"box\"];")
    for (i, node) in enumerate(nodes)
        l = card_name(get_card(node))
        println(io, "    \"$(i)\" [label = \"$(l)\"];")
    end
    println(io, "  }")
    println(io, "  subgraph {")
    println(io, "    node [shape = \"point\"];")
    for (j, var) in enumerate(output_vars)
        println(io, "    \"$(N + j)\" [label = \"$(var)\"];")
    end
    println(io, "  }")
    println(io)

    for edge in edges
        src, dst = Graphs.src(edge), Graphs.dst(edge)
        spec = if src ≤ N
            "[]"
        else
            var = output_vars[src - N]
            "[arrowhead = \"none\", label = \"$(var)\"]"
        end
        println(io, "  \"$(src)\" -> \"$(dst)\" ", spec, ";")
    end
    println(io, "}")
end