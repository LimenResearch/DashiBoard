# utils

@kwarg struct UnparsedDeps
    nodes::Vector{String} = String[]
    groups::Vector{String} = String[]
    cols::Vector{String} = String[]
    through::Vector{String} = String[]
end

@kwarg struct ParsedDeps
    nodes::Vector{Int} = Int[]
    groups::Vector{Int} = Int[]
    cols::Vector{String} = String[]
    through::Vector{Int} = Int[]
end

const DEPS_NAMES = ("nodes", "groups", "cols")

function is_deps(d::AbstractDict)
    return count(in(keys(d)), DEPS_NAMES) == 1 && keys(d) ⊆ (DEPS_NAMES..., "through")
end

@defaults struct DepsParser
    node_idxs::Dict{String, Int}
    group_idxs::Dict{String, Int}
    n_nodes::Int
    srcs::Vector{Int} = Int[]
    tgts::Vector{Int} = Int[]
    cols::OrderedSet{String} = OrderedSet{String}()
end

function parse_once(dp::DepsParser, d::AbstractDict, i::Integer)
    udeps::UnparsedDeps = construct(UnparsedDeps, d)
    pdeps = ParsedDeps(
        nodes = Int[dp.node_idxs[k] for k in udeps.nodes],
        groups = Int[dp.group_idxs[k] for k in udeps.groups],
        cols = udeps.cols,
        through = Int[dp.node_idxs[k] for k in udeps.through]
    )
    n_inputs = length(pdeps.nodes) + length(pdeps.through) + length(pdeps.groups)
    append!(dp.srcs, pdeps.nodes, pdeps.through, pdeps.groups .+ dp.n_nodes)
    append!(dp.tgts, StepRangeLen(i, 0, n_inputs)) # same as `fill` but does not allocate
    union!(dp.cols, pdeps.cols)
    return pdeps
end

function (dp::DepsParser)(d::AbstractDict, i::Integer)
    return is_deps(d) ? parse_once(dp, d, i) : map_into(Fix2(dp, i), StringDict, d)
end

(dp::DepsParser)(v::AbstractVector, i::Integer) = map_into(Fix2(dp, i), Vector{Any}, v)

(::DepsParser)(x::Any, ::Integer) = x

function dependency_graph(node_configs::AbstractVector, group_configs::AbstractDict)
    n_nodes, n_groups = length(node_configs), length(group_configs)
    node_configs′::Vector{StringDict} = node_configs

    ids = get_id.(node_configs′)
    allunique(ids) ||  throw(ArgumentError("Encountered nodes with equal `id`"))
    node_idxs = Dict{String, Int}(zip(ids, eachindex(ids)))

    group_configs′ = Vector{Vector{Any}}(undef, n_groups)
    group_idxs = Dict{String, Int}()
    for (i, (k, grp)) in enumerate(pairs(group_configs))
        group_configs′[i] = grp isa AbstractVector ? grp : Any[grp]
        group_idxs[k] = i
    end

    dp = DepsParser(node_idxs, group_idxs, n_nodes)

    # This also stores dependency edges in `dp`
    nodes = map(dp, node_configs′, eachindex(node_configs′))
    groups = map(dp, group_configs′, eachindex(group_configs′) .+ n_nodes)

    # create graph and manually add potentially missing vertices
    p = sortperm(dp.srcs)
    G = _digraph(view(dp.srcs, p), view(dp.tgts, p), n_nodes + n_groups)

    return G, nodes, groups, collect(String, dp.cols)
end

# Machinery to replace `ParsedDeps`

struct Configuration
    nodes::Vector{Node}
    outputs::Vector{Vector{String}}
    groups::Vector{Vector{String}}
end

# TODO: more general definition
function pass_through(x::AbstractVector, is::AbstractVector, nodes::AbstractVector)
    isempty(is) && return x
    suffix = join((node.card.suffix for node in view(nodes, is)), "_")
    return join_names.(x, suffix)
end

function to_cols(d::ParsedDeps, c::Configuration)
    nested = vcat(c.outputs[d.nodes], c.groups[d.groups], [d.cols])
    cols = reduce(vcat, nested)
    return pass_through(cols, d.through, c.nodes)
end

# Nested column computations

function replace_placeholders(d::AbstractDict, c::Configuration)
    return map_into(Fix2(replace_placeholders, c), StringDict, d)
end

function replace_placeholders(v::AbstractVector, c::Configuration)
    res = Any[]
    for el in v
        # append if `ParsedDeps`, else push
        x = replace_placeholders(el, c)
        el isa ParsedDeps ? append!(res, x) : push!(res, x)
    end
    return res
end

replace_placeholders(deps::ParsedDeps, c::Configuration) = to_cols(deps, c)

replace_placeholders(x::Any, c::Configuration) = x

function Configuration(G::DiGraph, nodes, groups)
    c = Configuration(
        similar(nodes, Node), similar(nodes, Vector{String}), similar(groups, Vector{String})
    )
    for i in topological_sort(G)
        if i ≤ length(c.nodes)
            node = Node(replace_placeholders(nodes[i], c))
            c.nodes[i] = node
            c.outputs[i] = get_node_outputs(node)
        else
            j = i - length(c.nodes)
            c.groups[j] = replace_placeholders(groups[j], c)
        end
    end
    return c
end
