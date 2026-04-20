# Generate `node_idxs` and `var_idxs` pairings for digraph as well as a list of variable names corresponding to the indices.
# A buffer dict `d` containing `var => var_idx` mappings is updated in place.
# It is assumed that all entries in `d` have distinct values within `length(nodes) + 1` and `length(nodes) + length(d)`.
function node_var_pairings!(f::F, d::AbstractDict{K}, nodes::AbstractVector{Node}) where {F, K}
    node_idxs, var_idxs, vars = Int[], Int[], K[]
    for (node_idx, node) in enumerate(nodes), var in f(node)
        def = length(nodes) + length(d) + 1
        var_idx = get!(d, var, def)
        push!(node_idxs, node_idx)
        push!(var_idxs, var_idx)
        (var_idx == def) && push!(vars, var)
    end
    return node_idxs, var_idxs, vars
end

struct EnrichedDiGraph{I <: Integer}
    g::DiGraph{I}
    source_vars::Vector{String}
    output_vars::Vector{String}
end

# We generate a graph whose vertices are: `nodes`, `output_vars`, `source_vars`, in this order.
# Source vars are input vars that are not included in the output of any node.
function EnrichedDiGraph(nodes::AbstractVector{Node})
    # generate variable to index dictionary
    d = Dict{String, Int}()
    # process `node => output_var` edges
    src_out, tgt_out, output_vars = node_var_pairings!(get_outputs, d, nodes)
    # process `input_var => node` edges
    tgt_in, src_in, source_vars = node_var_pairings!(get_inputs, d, nodes)

    # validate result
    N = length(nodes)
    repetead = unique(idx - N for (i, idx) in enumerate(tgt_out) if idx ≠ N + i)
    if !isempty(repetead)
        throw(ArgumentError("Columns $(output_vars[repetead]) would be overwritten"))
    end

    # `sortperm` here is fast (it uses counting sort for `Vector` of integers)
    # and makes digraph generation more efficient (see `DiGraph` docs).
    # As `tgt_in` is already sorted, edges will now be lexicographically sorted.
    p = sortperm(src_in)
    src::Vector{Int} = vcat(src_out, view(src_in, p))
    tgt::Vector{Int} = vcat(tgt_out, view(tgt_in, p))
    g = isempty(tgt) ? DiGraph{Int}() : DiGraph(Edge.(src, tgt))

    # return enriched graph
    return EnrichedDiGraph(g, source_vars, output_vars)
end

digraph(nodes::AbstractVector{Node}) = EnrichedDiGraph(nodes).g

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
function graphviz(io::IO, eg::EnrichedDiGraph, nodes::AbstractVector{Node})
    (; g, source_vars, output_vars) = eg

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
    for (j, var) in enumerate(Iterators.flatten([output_vars, source_vars]))
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
