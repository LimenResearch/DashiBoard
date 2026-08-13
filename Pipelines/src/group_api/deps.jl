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

# `Configuration` structure

struct IndexableConfigs{T}
    idxs::Dict{String, Int}
    configs::Vector{T}
    outputs::Vector{Vector{String}}
    deps::Vector{Vector{Deps}}
end

IndexableConfigs{T}(ks, vs) where {T} = IndexableConfigs{T}(zip(ks, vs))

function IndexableConfigs{T}(iter) where {T}
    n = length(iter)
    idxs = Dict{String, Int}()
    configs = Vector{T}(undef, n)
    outputs = Vector{Vector{String}}(undef, n)
    deps = Vector{Vector{Deps}}(undef, n)

    for (i, (k, v)) in enumerate(iter)
        dp = DepsParser()
        configs[i] = dp(v)
        deps[i] = dp.list
        idxs[k] = i
    end
    return IndexableConfigs{T}(idxs, configs, outputs, deps)
end

Base.length(ic::IndexableConfigs) = length(ic.configs)

get_indices(ic::IndexableConfigs, ks::AbstractVector) = get_indices(ic.idxs, ks)

get_outputs(ic::IndexableConfigs, ks::AbstractVector) = ic.outputs[get_indices(ic, ks)]

struct Configuration
    nodes::Vector{Node}
    node_configs::IndexableConfigs{StringDict}
    group_configs::IndexableConfigs{Union{Deps, Vector{Deps}}}
end

function Configuration(node_configs::AbstractVector, group_configs::AbstractDict)
    ids = get_id.(node_configs)
    allunique(ids) || throw(ArgumentError("Encountered nodes with equal `id`"))
    nds = IndexableConfigs{StringDict}(ids, node_configs)
    grps = IndexableConfigs{Union{Deps, Vector{Deps}}}(pairs(group_configs))
    return Configuration(similar(nds.configs, Node), nds, grps)
end

# TODO: more general definition
function pass_through(x::AbstractVector, ks::AbstractVector, c::Configuration)
    isempty(ks) && return x
    nodes = c.nodes[get_indices(c.node_configs, ks)]
    suffix = join([node.card.suffix for node in nodes], "_")
    return join_names.(x, suffix)
end

function to_columns(d::Deps, c::Configuration)
    nested = vcat(
        get_outputs(c.node_configs, d.nodes),
        get_outputs(c.group_configs, d.groups),
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
    (; nodes, node_configs, group_configs) = c
    if i ≤ length(c.nodes)
        node = Node(replace_placeholders(node_configs.configs[i], c))
        node_configs.outputs[i] = get_node_outputs(node)
        nodes[i] = node
    else
        j = i - length(nodes)
        group_configs.outputs[j] = replace_placeholders(group_configs.configs[j], c)
    end
    return c
end

function replace_placeholders!(c::Configuration, G::DiGraph)
    for i in topological_sort(G)
        replace_placeholders!(c, i)
    end
    return c
end
