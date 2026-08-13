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

function parse_deps!(deps_collection::AbstractVector, ls::AbstractVector)
    for i in eachindex(deps_collection, ls)
        dp = DepsParser()
        ls[i] = dp(ls[i])
        deps_collection[i] = dp.list
    end
    return deps_collection
end

# `Configuration` structure

struct Configuration
    node_idxs::Dict{String, Int}
    node_configs::Vector{StringDict}
    node_outputs::Vector{Vector{String}}
    nodes::Vector{Node}
    node_deps::Vector{Vector{Deps}}
    group_idxs::Dict{String, Int}
    group_configs::Vector{Any}
    groups::Vector{Vector{String}}
    group_deps::Vector{Vector{Deps}}
end

function separate_vals_idxs(::Type{T}, iter) where {T}
    vals, idx_dict = Vector{T}(undef, length(iter)), Dict{String, Int}()
    for (i, (k, v)) in enumerate(iter)
        vals[i] = v
        idx_dict[k] = i
    end
    return vals, idx_dict
end

function Configuration(node_configs::AbstractVector, group_configs::AbstractDict)
    group_configs′, group_idxs = separate_vals_idxs(Any, pairs(group_configs))
    node_configs′, node_idxs = separate_vals_idxs(
        StringDict, (get_id(n) => n for n in node_configs)
    )
    if length(node_idxs) < length(node_configs)
        throw(ArgumentError("Encountered nodes with equal `id`"))
    end
    node_outputs = similar(node_configs′, Vector{String})
    nodes = similar(node_configs′, Node)
    node_deps = similar(node_configs′, Vector{Deps})
    groups = similar(group_configs′, Vector{String})
    group_deps = similar(group_configs′, Vector{Deps})

    return Configuration(
        node_idxs, node_configs′, node_outputs, nodes, node_deps,
        group_idxs, group_configs′, groups, group_deps
    )
end

function parse_deps!(c::Configuration)
    parse_deps!(c.node_deps, c.node_configs)
    parse_deps!(c.group_deps, c.group_configs)
    return c
end

get_node_indices(c::Configuration, ks::AbstractVector) = get_indices(c.node_idxs, ks)
get_group_indices(c::Configuration, ks::AbstractVector) = get_indices(c.group_idxs, ks)

# TODO: more general definition
function pass_through(x::AbstractVector, ks::AbstractVector, c::Configuration)
    isempty(ks) && return x
    nodes = c.nodes[get_node_indices(c, ks)]
    suffix = join([node.card.suffix for node in nodes], "_")
    return join_names.(x, suffix)
end

function to_columns(d::Deps, c::Configuration)
    nested = vcat(
        c.node_outputs[get_node_indices(c, d.nodes)],
        c.groups[get_group_indices(c, d.groups)],
        [d.cols]
    )
    cols = reduce(vcat, nested)
    return pass_through(cols, d.through, c)
end

# Nested column computations

function replace_placeholders(d::AbstractDict, c::Configuration)
    return map_into(Fix2(replace_placeholders, c), StringDict, d)
end

function replace_placeholders(v::AbstractVector, c::Configuration)
    res = Any[]
    for el in v
        # append if `Deps`, else push
        x = replace_placeholders(el, c)
        el isa Deps ? append!(res, x) : push!(res, x)
    end
    return res
end

replace_placeholders(deps::Deps, c::Configuration) = to_columns(deps, c)

replace_placeholders(x::Any, c::Configuration) = x

function replace_placeholders!(c::Configuration, i::Integer)
    if i ≤ length(c.nodes)
        c.nodes[i] = Node(replace_placeholders(c.node_configs[i], c))
        c.node_outputs[i] = get_node_outputs(c.nodes[i])
    else
        j = i - length(c.nodes)
        c.groups[j] = replace_placeholders(c.group_configs[j], c)
    end
    return c
end

function replace_placeholders!(c::Configuration, G::DiGraph)
    for i in topological_sort(G)
        replace_placeholders!(c, i)
    end
    return c
end
