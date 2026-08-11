function dependency_graph(c::Configuration)
    edges, cols = Edge{Int}[], OrderedSet{String}()
    n_nodes, n_groups = length(c.nodes), length(c.groups)

    for (i, deplist) in enumerate(Iterators.flatten([c.node_deps, c.group_deps]))
        # Iterate over `deps` elements and add dependency edges
        for deps::Deps in deplist
            for node_key in Iterators.flatten([deps.nodes, deps.through])
                push!(edges, Edge(c.node_idxs[node_key], i))
            end
            for group_key in deps.groups
                push!(edges, Edge(n_nodes + c.group_idxs[group_key], i))
            end
            union!(cols, deps.cols)
        end
    end

    # create graph and manually add potentially missing vertices
    G = DiGraph(edges)
    add_vertices!(G, n_nodes + n_groups - nv(G))

    return G, collect(String, cols)
end

struct GroupDiGraph{I <: Integer} <: AbstractEnrichedDiGraph{I}
    g::DiGraph{I}
    source_vars::Vector{String}
    output_vars::Vector{String} # consider saving node_outputs instead
    groups::Vector{Vector{String}}
end

get_source_vars(eg::GroupDiGraph) = eg.source_vars
get_output_vars(eg::GroupDiGraph) = eg.output_vars

function Pipeline(
        nodes::AbstractVector,
        groups::AbstractDict,
        cols::Union{AbstractVector, Nothing} = nothing;
        validate_schema::Bool = true
    )

    validate_schema && validate_pipeline_schema(nodes, groups, cols)
    c = Configuration(nodes, groups) |> parse_deps!
    G, cols = dependency_graph(c)
    replace_placeholders!(c, G)
    eg = GroupDiGraph(G, cols, reduce(vcat, c.node_outputs), c.groups)
    return Pipeline(c.nodes, eg)
end
