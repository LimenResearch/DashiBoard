function is_special_dict(d::AbstractDict, k::AbstractString)
    return issetequal(keys(d), (k,)) || issetequal(keys(d), (k, "through"))
end

const is_node_dict = Fix2(is_special_dict, "nodes")
const is_group_dict = Fix2(is_special_dict, "groups")
const is_col_dict = Fix2(is_special_dict, "cols")

@kwdef struct Deps
    nodes::Vector{String} = String[]
    groups::Vector{String} = String[]
    cols::Vector{String} = String[]
end

function combine_deps(iter; recur::Bool = false)
    d = Deps()
    for el in iter
        deps = compute_deps(el; recur)
        append!(d.nodes, deps.nodes)
        append!(d.groups, deps.groups)
        append!(d.cols, deps.cols)
    end
    return Deps(; d.groups, d.nodes, d.cols)
end

function compute_deps(d::AbstractDict; recur::Bool = false)
    return if is_node_dict(d)
        Deps(nodes = to_stringlist(d["nodes"]))
    elseif is_group_dict(d)
        Deps(groups = to_stringlist(d["groups"]))
    elseif is_col_dict(d)
        Deps(cols = to_stringlist(d["cols"]))
    elseif recur
        combine_deps(values(d); recur)
    else
        Deps()
    end
end

compute_deps(v::AbstractVector; recur::Bool = false) = combine_deps(v; recur)

compute_deps(::Any; recur::Bool = false) = Deps()

function add_edges_and_cols!(
        edges::Vector{Edge{I}}, cols::AbstractSet,
        i::Integer, x::Union{AbstractDict, AbstractVector},
        node_idxs::AbstractDict, group_idxs::AbstractDict
    ) where {I <: Integer}

    deps = compute_deps(x; recur = true)
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
        add_edges_and_cols!(edges, cols, i, node, node_idxs, group_idxs)
    end
    for (i, group) in enumerate(group_vals)
        add_edges_and_cols!(edges, cols, n_nodes + i, group, node_idxs, group_idxs)
    end

    # create graph and manually add potentially missing vertices
    G = DiGraph(edges)
    add_vertices!(G, n_nodes + n_groups - nv(G))

    return G, group_keys => group_vals, collect(String, cols)
end
