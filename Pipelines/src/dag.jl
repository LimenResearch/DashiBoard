repeated_keys(cs) = Iterators.flatmap(splat(Iterators.repeated), pairs(cs))
lazy_pairs(cs, xs) = Iterators.map(=>, repeated_keys(cs), xs)

function output_dict(output_vars)
    d = Dict{String, Int}(Iterators.map(reverse, enumerate(output_vars)))
    repeated = unique(var for (i, var) in enumerate(output_vars) if i ≠ get!(d, var, i))
    isempty(repeated) || throw(ArgumentError("Columns $(repeated) would be overwritten"))
    return d
end

function flatten_and_count!(f::F, vals::AbstractVector, v::AbstractVector) where {F}
    counts = fill(0, length(v))
    for (i, x) in pairs(v)
        l = length(vals)
        append!(vals, f(x))
        counts[i] = length(vals) - l
    end
    return counts::Vector{Int}
end

##

struct EnrichedDiGraph
    g::DiGraph{Int}
    source_indices::Vector{Vector{Int}}
    source_vars::Vector{String}
    output_vars::Vector{String}
end

digraph(nodes::AbstractVector{Node}) = EnrichedDiGraph(nodes).g

function EnrichedDiGraph(nodes::AbstractVector{Node})
    Base.require_one_based_indexing(nodes)
    inputs, source_vars, output_vars = Int[], OrderedSet{String}(), String[]
    # preprocess outbound edges
    output_counts = flatten_and_count!(get_outputs, output_vars, nodes)
    # generate variable to index dictionary and validate result
    d = output_dict(output_vars)
    # also store
    # preprocess inbound edges
    input_counts = flatten_and_count!(inputs, nodes) do node
        vars = get_inputs(node)
        idxs = get.((d,), vars, 0)
        is_source = idxs .== 0
        union!(source_vars, view(vars, is_source))
        return view(idxs, .!is_source)
    end
    # return enriched graph
    g = digraph(inputs, input_counts, output_counts)

    return EnrichedDiGraph(
        g,
        Vector{Int}[],
        collect(String, source_vars),
        output_vars
    )
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
        label = get_label(get_card(node))
        fillcolor = get_update(node) ? "white" : "transparent"
        println(io, "    \"$(i)\" [label = \"$(label)\" fillcolor = \"$(fillcolor)\"];")
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
