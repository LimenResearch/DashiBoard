struct GroupDiGraph{I <: Integer} <: AbstractEnrichedDiGraph{I}
    g::DiGraph{I}
    source_vars::Vector{String}
    output_vars::Vector{String} # consider saving node outputs separately instead
    groups::Vector{Vector{String}}
    group_names::Vector{String}
end

get_source_vars(eg::GroupDiGraph) = eg.source_vars
get_output_vars(eg::GroupDiGraph) = eg.output_vars

function Pipeline(
        node_configs::AbstractVector,
        group_configs::AbstractDict,
        available_cols::Maybe{AbstractVector} = nothing;
        validate_schema::Bool = true
    )

    validate_schema && validate_pipeline_schema(node_configs, group_configs, available_cols)
    G, nodes, (group_names, groups), cols = dependency_graph(node_configs, group_configs)
    n_nodes = length(nodes)
    c = Context(G, nodes, groups)
    # `reduce` over zero outputs throws a "reducing over an empty collection" error
    V = eltype(c.outputs)
    output_vars = n_nodes == 0 ? similar(V, 0) : reduce(vcat, view(c.outputs, 1:n_nodes))
    group_outputs = c.outputs[(n_nodes + 1):end]
    eg = GroupDiGraph(G, cols, output_vars, group_outputs, group_names)
    return Pipeline(c.nodes, eg)
end

# A `GroupDiGraph`'s vertices are the nodes followed by the groups — it has no variable vertices,
# unlike an `EnrichedDiGraph`. So this cannot share the `EnrichedDiGraph` method by widening its
# signature to the abstract type: that method labels vertex `N + j` with the j-th variable, which
# here would silently attach variable names to group vertices instead of failing.
function graphviz(io::IO, eg::GroupDiGraph, nodes::AbstractVector{Node})
    (; g, group_names) = eg
    N = length(nodes)

    println(io, "digraph G{")
    println(io, "  bgcolor = \"transparent\";", "\n")

    println(io, "  subgraph cards {")
    println(io, "    node [shape = \"box\" style = \"filled\"];")
    for (i, node) in enumerate(nodes)
        label = get_label(node)
        fillcolor = get_update(node) ? "white" : "transparent"
        println(io, "    \"$(i)\" [label = \"$(label)\" fillcolor = \"$(fillcolor)\"];")
    end
    println(io, "  }", "\n")

    println(io, "  subgraph groups {")
    println(io, "    node [shape = \"ellipse\"];")
    for (j, name) in enumerate(group_names)
        println(io, "    \"$(N + j)\" [label = \"$(name)\"];")
    end
    println(io, "  }", "\n")

    # Edges run dependency → dependent, so a single arrowhead style is right throughout.
    println(io, "  edge [arrowhead = \"normal\"];")
    for src in 1:nv(g)
        outs = outneighbors(g, src)
        isempty(outs) && continue
        print(io, "  ", "\"", src, "\"", " -> {\"")
        join(io, outs, "\" \"")
        println(io, "\"};")
    end

    return println(io, "}")
end
