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

function generate_dag(nodes::AbstractVector, groups::T) where {T <: AbstractDict}
    g = isordered(T) ? groups : OrderedDict(groups)
    return _generate_dag(nodes, g)
end

function _generate_dag(nodes::AbstractVector, groups::AbstractDict)
    n_nodes = length(nodes)
    n_groups = length(groups)

    node_idxs = Dict{Union{String, Nothing}, Int}(
        get(n, "label", nothing) => i for (i, n) in enumerate(nodes)
    )

    group_keys = collect(String, keys(groups))
    group_idxs = Dict(k => i for (i, k) in enumerate(group_keys))

    cols = OrderedSet{String}()
    G = DiGraph(n_nodes + n_groups)

    for (i, node) in enumerate(nodes)
        deps = compute_deps(node; recur = true)
        for node_key in deps.nodes
            add_edge!(G, node_idxs[node_key] => i)
        end
        for group_key in deps.groups
            add_edge!(G, n_nodes + group_idxs[group_key] => i)
        end
        union!(cols, deps.cols)
    end
    for (i, group) in enumerate(values(groups))
        deps = compute_deps(group; recur = true)
        for group_key in deps.groups
            add_edge!(G, n_nodes + group_idxs[group_key] => n_nodes + i)
        end
        for node_key in deps.nodes
            add_edge!(G, node_idxs[node_key] => n_nodes + i)
        end
        union!(cols, deps.cols)
    end
    return G, group_keys, collect(String, cols)
end
