function add_edges_and_cols!(
        edges::Vector{Edge{I}}, cols::AbstractSet,
        i::Integer, x::Union{AbstractDict, AbstractVector},
        node_idxs::AbstractDict, group_idxs::AbstractDict;
        recur::Bool = false
    ) where {I <: Integer}

    deps = compute_deps(x; recur)
    for node_key in deps.nodes
        push!(edges, Edge(node_idxs[node_key], i))
    end
    for group_key in deps.groups
        push!(edges, Edge(group_idxs[group_key], i))
    end
    union!(cols, deps.cols)
    return edges
end

function generate_dag(nodes::AbstractVector, groups::AbstractDict)
    n_nodes, n_groups = length(nodes), length(groups)

    group_keys = Vector{String}(undef, n_groups)
    group_vals = Vector{valtype(groups)}(undef, n_groups)
    for (i, (k, v)) in enumerate(pairs(groups))
        group_keys[i] = k
        group_vals[i] = v
    end

    node_idxs = Dict{Union{String, Nothing}, Int}(
        get(n, "label", nothing) => i for (i, n) in enumerate(nodes)
    )

    group_idxs = Dict(k => i + n_nodes for (i, k) in enumerate(group_keys))

    cols = OrderedSet{String}()
    edges = Edge{Int}[]

    for (i, node) in enumerate(nodes)
        add_edges_and_cols!(edges, cols, i, node, node_idxs, group_idxs; recur = true)
    end
    for (i, group) in enumerate(group_vals)
        add_edges_and_cols!(edges, cols, n_nodes + i, group, node_idxs, group_idxs)
    end

    # create graph and manually add potentially missing vertices
    G = DiGraph(edges)
    add_vertices!(G, n_nodes + n_groups - nv(G))

    return G, group_keys => group_vals, collect(String, cols)
end

struct NodeDiGraph{I <: Integer}
    nodes::Vector{Node}
    g::DiGraph{I}
end

function NodeDiGraph(nodes::AbstractVector, groups::AbstractDict)
    G, (group_keys, group_vals), cols = generate_dag(nodes, groups)

    n_nodes = length(nodes)
    ps = Params()

    for v in topological_sort(G)
        if v ≤ n_nodes
            config = replace_placeholders(nodes[v], ps; recur = true)
            node = Node(config, adjust = true)
            ps.nodes[get_label(node)] = node
        else
            j = v - n_nodes
            group_key = group_keys[j]
            group_val = group_vals[j]
            ps.groups[group_key] = replace_placeholders(group_val, ps)
        end
    end
    return G
end
