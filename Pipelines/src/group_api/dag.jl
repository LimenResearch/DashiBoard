function dependency_graph!(ps::Params)
    edges, cols = Edge{Int}[], OrderedSet{String}()

    n_nodes, n_groups = length(ps.nodes), length(ps.groups)
    node_deps::Vector{Vector{Deps}} = parse_and_return_deps!(ps.node_configs)
    group_deps::Vector{Vector{Deps}} = parse_and_return_deps!(ps.group_configs)

    for (i, deplist) in enumerate(Iterators.flatten([node_deps, group_deps]))
        # Iterate over `deps` elements and add dependency edges
        for deps::Deps in deplist
            for node_key in Iterators.flatten([deps.nodes, deps.through])
                push!(edges, Edge(ps.node_idxs[node_key], i))
            end
            for group_key in deps.groups
                push!(edges, Edge(n_nodes + ps.group_idxs[group_key], i))
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

function Pipeline(nodes::AbstractVector, groups::AbstractDict)
    ps = Params(nodes, groups) # FIXME: better name, `Configuration?`
    G, cols = dependency_graph!(ps)
    for i in topological_sort(G)
        replace_placeholders!(ps, i)
    end
    eg = GroupDiGraph(G, cols, reduce(vcat, ps.node_outputs), ps.groups)
    return Pipeline(ps.nodes, eg)
end
