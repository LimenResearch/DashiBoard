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

get_list(d::AbstractDict, k)::Vector{String} = to_stringlist(get(d, k, nothing))

get_through(d::AbstractDict) = get_list(d, "through")

function basic_deps(d::AbstractDict)::Union{Deps, Nothing}
    return if is_node_dict(d)
        Deps(nodes = get_list(d, "nodes"))
    elseif is_group_dict(d)
        Deps(groups = get_list(d, "groups"))
    elseif is_col_dict(d)
        Deps(cols = get_list(d, "cols"))
    else
        nothing
    end
end

function compute_deps(d::AbstractDict; recur::Bool = false)
    deps = basic_deps(d)
    !isnothing(deps) && (append!(deps.nodes, get_through(d)); return deps)
    return recur ? combine_deps(values(d); recur) : Deps()
end

compute_deps(v::AbstractVector; recur::Bool = false) = combine_deps(v; recur)

compute_deps(::Any; recur::Bool = false) = Deps()

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

# TODO: more general definition
function pass_through(x::AbstractVector, ks, node_params)
    nodes = Node[node_params[k] for k in ks]
    suffix = join([node.card.suffix for node in nodes], "_")
    return join_names.(x, suffix)
end

function to_columns(el, node_params, group_params)
    x::Union{Vector{String}, Nothing} = if is_node_dict(el)
        reduce(
            vcat,
            Vector{String}[
                get_node_outputs(node_params[k]) for k in get_list(el, "nodes")
            ]
        )
    elseif is_group_dict(el)
        reduce(vcat, Vector{String}[group_params[k] for k in get_list(el, "groups")])
    elseif is_col_dict(el)
        get_list(el, "cols")
    else
        nothing
    end
    isnothing(x) && return nothing
    return pass_through(x, to_stringlist(get(el, "through", nothing)), node_params)
end

function replace_placeholders(config::AbstractDict, node_params, group_params)
    x = to_columns(config, node_params, group_params)
    isnothing(x) || return x
    res = Dict{String, Any}()
    for (k, v) in pairs(config)
        res[k] = replace_placeholders(v, node_params, group_params)
    end
    return res
end

function replace_placeholders(config::AbstractVector, node_params, group_params)
    res = Any[]
    for el in config
        x = replace_placeholders(el, node_params, group_params)
        # append if placeholder was replaced, else push
        if (el isa AbstractDict) && (x isa AbstractVector)
            append!(res, x)
        else
            push!(res, x)
        end
    end
    return res
end

replace_placeholders(x::Any, _, _) = x

struct NodeDiGraph{I <: Integer}
    nodes::Vector{Node}
    g::DiGraph{I}
end

function NodeDiGraph(nodes::AbstractVector, groups::AbstractDict)
    G, (group_keys, group_vals), cols = generate_dag(nodes, groups)

    n_nodes = length(nodes)
    node_params = Dict{String, Node}()
    group_params = Dict{String, Vector{String}}()

    for v in topological_sort(G)
        if v ≤ n_nodes
            config = replace_placeholders(nodes[v], node_params, group_params)
            node = Node(config)
            node_params[get_label(node)] = node
        else
            j = v - n_nodes
            group_key = group_keys[j]
            group_val = group_vals[j]
            group_params[group_key] =
                replace_placeholders(group_val, node_params, group_params)
        end
    end
    return G
end
