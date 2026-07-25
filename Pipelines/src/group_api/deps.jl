# utils

@kwarg struct Deps
    nodes::Vector{String} = String[]
    groups::Vector{String} = String[]
    cols::Vector{String} = String[]
    through::Vector{String} = String[]
end

const DEPS_NAMES = ("nodes", "groups", "cols")

function is_deps(d::AbstractDict)
    return count(in(keys(d)), DEPS_NAMES) == 1 && keys(d) ⊆ (DEPS_NAMES..., "through")
end

struct DepsParser
    list::Vector{Deps}
end

DepsParser() = DepsParser(Deps[])

parse_once(dp::DepsParser, d::AbstractDict) = (deps = construct(Deps, d); push!(dp.list, deps); deps)

(dp::DepsParser)(d::AbstractDict) = is_deps(d) ? parse_once(dp, d) : map_into(dp, StringDict, d)
(dp::DepsParser)(v::AbstractVector) = map_into(dp, Vector{Any}, v)
(::DepsParser)(x::Any) = x

function parse_and_return_deps!(ls::AbstractVector)
    deps_collection = similar(ls, Vector{Deps})
    for i in eachindex(ls)
        dp = DepsParser()
        ls[i] = dp(ls[i])
        deps_collection[i] = dp.list
    end
    return deps_collection
end

# Compute columns

struct Params
    node_idxs::Dict{String, Int}
    node_configs::Vector{StringDict}
    node_outputs::Vector{Vector{String}}
    nodes::Vector{Node}
    group_idxs::Dict{String, Int}
    group_configs::Vector{Any}
    groups::Vector{Vector{String}}
end

function separate_vals_idxs(::Type{T}, iter) where {T}
    vals, idx_dict = Vector{T}(undef, length(iter)), Dict{String, Int}()
    for (i, (k, v)) in enumerate(iter)
        vals[i] = v
        isnothing(k) || (idx_dict[k] = i)
    end
    return vals, idx_dict
end

function Params(node_configs::AbstractVector, group_configs::AbstractDict)
    group_configs′, group_idxs = separate_vals_idxs(Any, pairs(group_configs))
    node_configs′, node_idxs = separate_vals_idxs(
        StringDict, get(n, "label", nothing) => n for n in node_configs
    )
    node_outputs = similar(node_configs′, Vector{String})
    nodes = similar(node_configs′, Node)
    groups = similar(group_configs′, Vector{String})

    return Params(
        node_idxs, node_configs′, node_outputs, nodes,
        group_idxs, group_configs′, groups
    )
end

get_nodes(ps::Params, ks::AbstractVector) = ps.nodes[get_indices(ps.node_idxs, ks)]
get_node_outputs(ps::Params, ks::AbstractVector) = ps.node_outputs[get_indices(ps.node_idxs, ks)]
get_groups(ps::Params, ks::AbstractVector) = ps.groups[get_indices(ps.group_idxs, ks)]

# TODO: more general definition
function pass_through(x::AbstractVector, ks::AbstractVector, ps::Params)
    isempty(ks) && return x
    nodes = get_nodes(ps, ks)
    suffix = join([node.card.suffix for node in nodes], "_")
    return join_names.(x, suffix)
end

function to_columns(d::Deps, ps::Params)
    nested = vcat(get_node_outputs(ps, d.nodes), get_groups(ps, d.groups), [d.cols])
    cols = reduce(vcat, nested)
    return pass_through(cols, d.through, ps)
end

# Nested column computations

replace_placeholders(d::AbstractDict, ps::Params) = map_into(Fix2(replace_placeholders, ps), StringDict, d)

function replace_placeholders(v::AbstractVector, ps::Params)
    res = Any[]
    for el in v
        # append if `Deps`, else push
        el isa Deps ? append!(res, to_columns(el, ps)) : push!(res, replace_placeholders(el, ps))
    end
    return res
end

replace_placeholders(deps::Deps, ps::Params) = to_columns(deps, ps)

replace_placeholders(x::Any, ps::Params) = x

function replace_placeholders!(ps::Params, i::Integer)
    if i ≤ length(ps.nodes)
        ps.nodes[i] = Node(replace_placeholders(ps.node_configs[i], ps))
        ps.node_outputs[i] = get_node_outputs(ps.nodes[i])
    else
        j = i - length(ps.nodes)
        ps.groups[j] = replace_placeholders(ps.group_configs[j], ps)
    end
    return ps
end
