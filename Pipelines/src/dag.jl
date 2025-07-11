repeated_keys(cs) = Iterators.flatmap(splat(Iterators.repeated), pairs(cs))
lazy_pairs(cs, xs) = Iterators.map(=>, repeated_keys(cs), xs)

positive_values(d, ks) = Iterators.filter(>(0), Iterators.map(Fix1(getindex, d), ks))
positive_values(d) = Fix1(positive_values, d)

function combine_vars(colnames, output_vars)
    d = Dict{String, Int}(Iterators.zip(colnames, Iterators.repeated(0)))
    repeated = unique(var for (i, var) in enumerate(output_vars) if i ≠ get!(d, var, i))
    isempty(repeated) || throw(ArgumentError("Columns $(repeated) would be overwritten"))
    return d
end

function flatten_and_count(f::F, ::Type{T}, v::AbstractVector) where {F, T}
    vals, counts = T[], fill(0, length(v))
    for (i, x) in pairs(v)
        l = length(vals)
        append!(vals, f(x))
        counts[i] = length(vals) - l
    end
    return vals::Vector{T}, counts::Vector{Int}
end

##

function digraph(nodes::AbstractVector{Node}, colnames::AbstractVector{<:AbstractString})
    g, _ = digraph_metadata(nodes, colnames)
    return g
end

function digraph_metadata(nodes::AbstractVector{Node}, colnames::AbstractVector{<:AbstractString})
    Base.require_one_based_indexing(nodes)
    # preprocess outbound edges
    output_vars, output_counts = flatten_and_count(get_outputs, String, nodes)
    # generate variable to index dictionary and validate result
    d = combine_vars(colnames, output_vars)
    # preprocess inbound edges
    inputs, input_counts = flatten_and_count(positive_values(d) ∘ get_inputs, Int, nodes)
    # return graph and variable names
    return digraph(inputs, input_counts, output_counts), output_vars
end

function digraph(
        inputs::AbstractVector{<:Integer},
        input_counts::AbstractVector{<:Integer},
        output_counts::AbstractVector{<:Integer}
    )

    # compute number of nodes, input and output variables
    n_inputs, n_outputs, N = sum(input_counts), sum(output_counts), length(output_counts)

    # counting sort
    counts = fill(0, n_outputs + 1)
    for input in inputs
        counts[input + 1] += 1
    end
    for i in 1:n_outputs
        counts[i + 1] += counts[i]
    end

    # initialize and fill `edges` array
    edges = fill(Edge(0, 0), n_outputs + n_inputs)
    for (node_idx, output) in lazy_pairs(output_counts, 1:n_outputs)
        edge_idx = output
        edges[edge_idx] = Edge(node_idx, N + output)
    end
    for (node_idx, input) in lazy_pairs(input_counts, inputs)
        edge_idx = n_outputs + (counts[input] += 1)
        edges[edge_idx] = Edge(N + input, node_idx)
    end

    return DiGraph(edges)
end

##

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
        h ≥ 0 && push!(ls[h + 1], i)
    end
    return ls
end

##

# TODO: make look customizable (esp., match font with AlgebraOfGraphics)
function graphviz(io::IO, g::DiGraph, nodes::AbstractVector{Node}, vars::AbstractVector{<:AbstractString})
    N = length(nodes)

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
