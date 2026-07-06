# utils

get_list(d::AbstractDict, k)::Vector{String} = to_stringlist(get(d, k, nothing))

get_through(d::AbstractDict) = get_list(d, "through")

# TODO: more general definition
function pass_through(x::AbstractVector, ks, node_params)
    isempty(ks) && return x
    nodes = Node[node_params[k] for k in ks]
    suffix = join([node.card.suffix for node in nodes], "_")
    return join_names.(x, suffix)
end

function is_special_dict(d::AbstractDict, k::AbstractString)
    return issetequal(keys(d), (k,)) || issetequal(keys(d), (k, "through"))
end

# Compute dependencies

@kwdef struct Deps
    nodes::Vector{String} = String[]
    groups::Vector{String} = String[]
    cols::Vector{String} = String[]
end

function merge_deps!(d::Deps, deps::Deps)
    append!(d.nodes, deps.nodes)
    append!(d.groups, deps.groups)
    append!(d.cols, deps.cols)
    return d
end

abstract type AbstractStructure end

struct NodeStructure <: AbstractStructure end
struct GroupStructure <: AbstractStructure end
struct ColStructure <: AbstractStructure end

const structures = (NodeStructure(), GroupStructure(), ColStructure())

function try_structures(f, args...)
    return foldl(structures, init = nothing) do acc, s
        isnothing(acc) ? f(s, args...) : acc
    end
end

obeys(::NodeStructure, d) = is_special_dict(d, "nodes")
obeys(::GroupStructure, d) = is_special_dict(d, "groups")
obeys(::ColStructure, d) = is_special_dict(d, "cols")

_direct_deps(::NodeStructure, d) = Deps(nodes = get_list(d, "nodes"))
_direct_deps(::GroupStructure, d) = Deps(groups = get_list(d, "groups"))
_direct_deps(::ColStructure, d) = Deps(cols = get_list(d, "cols"))

function direct_deps(s::AbstractStructure, d::AbstractDict)
    obeys(s, d) || return nothing
    return merge_deps!(_direct_deps(s, d), Deps(nodes = get_through(d)))
end

direct_deps(d::AbstractDict) = try_structures(direct_deps, d)

# Nested dependency computations

function iterator_deps(iter; recur::Bool = false)
    res = Deps()
    for el in iter
        merge_deps!(res, compute_deps(el; recur))
    end
    return res
end

function compute_deps(d::AbstractDict; recur::Bool = false)
    deps = direct_deps(d)
    isnothing(deps) || return deps
    recur || return Deps()
    return iterator_deps(values(d); recur)
end

compute_deps(v::AbstractVector; recur::Bool = false) = iterator_deps(v; recur)

compute_deps(::Any; recur::Bool = false) = Deps()

# Compute columns

struct Params
    nodes::Dict{String, Node}
    groups::Dict{String, Vector{String}}
end

Params() = Params(Dict{String, Node}(), Dict{String, Vector{String}}())

function _to_columns(::NodeStructure, d::AbstractDict, ps::Params)
    outputs = Vector{String}[
        get_node_outputs(ps.nodes[k]) for k in get_list(d, "nodes")
    ]
    return reduce(vcat, outputs)
end

function _to_columns(::GroupStructure, d::AbstractDict, ps::Params)
    grps = Vector{String}[ps.groups[k] for k in get_list(d, "groups")]
    return reduce(vcat, grps)
end

function _to_columns(::ColStructure, d::AbstractDict, ::Params)
    return get_list(d, "cols")
end

function to_columns(s::AbstractStructure, d::AbstractDict, ps::Params)
    obeys(s, d) || return nothing
    cols = _to_columns(s, d, ps)
    return pass_through(cols, get_through(d), ps.nodes)
end

to_columns(d::AbstractDict, ps::Params) = try_structures(to_columns, d, ps)

# Nested column computations

function replace_placeholders(config::AbstractDict, ps::Params; recur::Bool = false)
    x = to_columns(config, ps)
    isnothing(x) || return x
    recur || return config

    res = Dict{String, Any}()
    for (k, v) in pairs(config)
        res[k] = replace_placeholders(v, ps; recur)
    end
    return res
end

function replace_placeholders(config::AbstractVector, ps::Params; recur::Bool = false)
    res = Any[]
    for el in config
        x = replace_placeholders(el, ps::Params; recur)
        # append if placeholder was replaced, else push
        if (el isa AbstractDict) && (x isa AbstractVector)
            append!(res, x)
        else
            push!(res, x)
        end
    end
    return res
end

replace_placeholders(x::Any, ::Params; recur::Bool = false) = x

# schema definitions

function _deps_schema_item(
        name::AbstractString, items::AbstractDict;
        singular::Bool = false
    )
    _schema = StringDict(
        "type" => "array",
        "items" => items,
        "minItems" => 1
    )
    singular && (_schema["maxItems"] = 1)

    return Dict(
        "type" => "object",
        "properties" => StringDict(
            name => _schema,
            "through" => JSON_NODES
        ),
        "required" => [name],
        "additionalProperties" => false
    )
end

function deps_schema_item(deps::Deps; singular::Bool = false)
    conds = StringDict[
        Dict("required" => ["nodes"]),
        Dict("required" => ["groups"]),
        Dict("required" => ["cols"]),
    ]
    results = StringDict[
        _deps_schema_item("nodes", JSON_NODE; singular),
        _deps_schema_item("groups", JSON_GROUP; singular),
        _deps_schema_item("cols", JSON_COL; singular),
    ]
    return Dict(
        "anyOf" => conds,
        "allOf" => conditional_schema.(conds, results)
    )
end

function schema_definitions(deps::Deps)
    nodes_schema = Dict(
        "type" => "array",
        "items" => JSON_NODE
    )
    node_schema = json_enum(deps.nodes)
    group_schema = json_enum(deps.groups)
    col_schema = json_enum(deps.cols)

    variable_schema = deps_schema_item(deps; singular = true)
    variables_schema = Dict(
        "type" => "array",
        "items" => deps_schema_item(deps),
        "default" => String[]
    )
    nonempty_variables_schema = Dict(
        "type" => "array",
        "items" => deps_schema_item(deps),
        "minItems" => 1
    )

    return Dict(
        "nodes" => nodes_schema,
        "node" => node_schema,
        "group" => group_schema,
        "col" => col_schema,
        "variable" => variable_schema,
        "variables" => variables_schema,
        "nonempty_variables" => nonempty_variables_schema,
    )
end
