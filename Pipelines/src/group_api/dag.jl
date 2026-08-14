function add_edges!(
        edges::AbstractVector, cols::AbstractSet, c::Configuration,
        deps::Deps, i::Integer, n_nodes::Integer
    )
    for node_keys in (deps.nodes, deps.through), node_key in node_keys
        push!(edges, Edge(c.nodes.idxs[node_key], i))
    end
    for group_key in deps.groups
        push!(edges, Edge(n_nodes + c.groups.idxs[group_key], i))
    end
    union!(cols, deps.cols)
    return deps
end

function add_edges!(
        edges::AbstractVector, cols::AbstractSet, c::Configuration,
        config::Union{AbstractDict, AbstractVector}, i::Integer, n_nodes::Integer
    )
    # Iterate over `deps` elements and add dependency edges
    dp = DepsParser()
    parsed = dp(config)
    for deps::Deps in dp.list
        add_edges!(edges, cols, c, deps, i, n_nodes)
    end
    return parsed
end

function dependency_graph!(c::Configuration)
    edges, cols = Edge{Int}[], OrderedSet{String}()
    n_nodes, n_groups = length(c.nodes), length(c.groups)

    for i in eachindex(c.nodes.configs)
        c.nodes.configs[i] = add_edges!(edges, cols, c, c.nodes.configs[i], i, n_nodes)
    end
    for i in eachindex(c.groups.configs)
        c.groups.configs[i] = add_edges!(edges, cols, c, c.groups.configs[i], n_nodes + i, n_nodes)
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
    c = Configuration(nodes, groups)
    G, cols = dependency_graph!(c)
    replace_placeholders!(c, G)
    eg = GroupDiGraph(
        G, cols,
        reduce(vcat, c.nodes.outputs),
        c.groups.outputs
    )
    return Pipeline(c.nodes.vals, eg)
end
