struct GroupDiGraph{I <: Integer} <: AbstractEnrichedDiGraph{I}
    g::DiGraph{I}
    source_vars::Vector{String}
    output_vars::Vector{String} # consider saving node outputs separately instead
    groups::Vector{Vector{String}}
end

get_source_vars(eg::GroupDiGraph) = eg.source_vars
get_output_vars(eg::GroupDiGraph) = eg.output_vars

function Pipeline(
        node_configs::AbstractVector,
        group_configs::AbstractDict,
        available_cols::Union{AbstractVector, Nothing} = nothing;
        validate_schema::Bool = true
    )

    validate_schema && validate_pipeline_schema(node_configs, group_configs, available_cols)
    complete_node_configs = complete_node_list(node_configs)
    G, nodes, groups, cols = dependency_graph(node_configs, group_configs)
    n_nodes = length(nodes)
    c = Context(G, nodes, groups)
    output_vars = reduce(vcat, view(c.outputs, 1:n_nodes))
    group_outputs = c.outputs[(n_nodes + 1):end]
    eg = GroupDiGraph(G, cols, output_vars, group_outputs)
    return Pipeline(c.nodes, eg)
end
