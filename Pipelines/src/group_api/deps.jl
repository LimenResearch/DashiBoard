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

function parse_once(dp::DepsParser, d::AbstractDict)
    deps = construct(Deps, d)
    push!(dp.list, deps)
    return deps
end

(dp::DepsParser)(d::AbstractDict) = is_deps(d) ? parse_once(dp, d) : map_into(dp, StringDict, d)
(dp::DepsParser)(v::AbstractVector) = map_into(dp, Vector{Any}, v)
(::DepsParser)(x::Any) = x

standardize(d::AbstractDict)::StringDict = d
standardize(deps::Deps)::Vector{Deps} = Deps[deps]
standardize(v::AbstractVector)::Vector{Deps} = v

# `Configuration` structure

struct IndexableConfigs{C, V}
    idxs::Dict{String, Int}
    configs::Vector{C}
    vals::Vector{V}
    outputs::Vector{Vector{String}}
    deps::Vector{Vector{Deps}}
end

function IndexableConfigs{C, V}(iter) where {C, V}
    n = length(iter)
    idxs = Dict{String, Int}()
    configs = Vector{C}(undef, n)
    vals = Vector{V}(undef, n)
    outputs = Vector{Vector{String}}(undef, n)
    deps = Vector{Vector{Deps}}(undef, n)

    for (i, (k, v)) in enumerate(iter)
        dp = DepsParser()
        parsed = dp(v)
        configs[i] = standardize(parsed)
        deps[i] = dp.list
        idxs[k] = i
    end
    return IndexableConfigs{C, V}(idxs, configs, vals, outputs, deps)
end

IndexableConfigs{C, V}(ks, vs) where {C, V} = IndexableConfigs{C, V}(zip(ks, vs))

Base.length(ic::IndexableConfigs) = length(ic.configs)

get_vals(ic::IndexableConfigs, ks::AbstractVector) = ic.vals[get_indices(ic.idxs, ks)]
get_outputs(ic::IndexableConfigs, ks::AbstractVector) = ic.outputs[get_indices(ic.idxs, ks)]

struct Configuration
    nodes::IndexableConfigs{StringDict, Node}
    groups::IndexableConfigs{Vector{Deps}, Nothing}
end

function Configuration(node_configs::AbstractVector, group_configs::AbstractDict)
    ids = get_id.(node_configs)
    allunique(ids) || throw(ArgumentError("Encountered nodes with equal `id`"))
    nodes = IndexableConfigs{StringDict, Node}(ids, node_configs)
    groups = IndexableConfigs{Vector{Deps}, Nothing}(pairs(group_configs))
    return Configuration(nodes, groups)
end

# TODO: more general definition
function pass_through(x::AbstractVector, ks::AbstractVector, c::Configuration)
    isempty(ks) && return x
    nodes = get_vals(c.nodes, ks)
    suffix = join([node.card.suffix for node in nodes], "_")
    return join_names.(x, suffix)
end

function to_columns(d::Deps, c::Configuration)
    nested = vcat(
        get_outputs(c.nodes, d.nodes),
        get_outputs(c.groups, d.groups),
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

function replace_placeholders!(c::Configuration, G::DiGraph)
    for i in topological_sort(G)
        if i ≤ length(c.nodes)
            node = Node(replace_placeholders(c.nodes.configs[i], c))
            c.nodes.vals[i] = node
            c.nodes.outputs[i] = get_node_outputs(node)
        else
            j = i - length(c.nodes)
            c.groups.outputs[j] = replace_placeholders(c.groups.configs[j], c)
        end
    end
    return c
end
