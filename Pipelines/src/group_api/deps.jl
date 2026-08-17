# utils

@kwarg struct UnparsedDeps
    nodes::Vector{String} = String[]
    groups::Vector{String} = String[]
    cols::Vector{String} = String[]
    through::Vector{String} = String[]
end

struct ParsedDeps
    from::Vector{Int}
    cols::Vector{String}
    through::Vector{Int}
end

const DEPS_NAMES = ("nodes", "groups", "cols")

function is_deps(d::AbstractDict)
    return count(in(keys(d)), DEPS_NAMES) == 1 && keys(d) ⊆ (DEPS_NAMES..., "through")
end

@defaults struct DepsParser
    node_idxs::Dict{String, Int}
    group_idxs::Dict{String, Int}
    srcs::Vector{Int} = Int[]
    tgts::Vector{Int} = Int[]
    cols::OrderedSet{String} = OrderedSet{String}()
end

function ParsedDeps(dp::DepsParser, udeps::UnparsedDeps)
    nodes = Int[dp.node_idxs[k] for k in udeps.nodes]
    groups = Int[dp.group_idxs[k] for k in udeps.groups]
    cols = udeps.cols
    through = Int[dp.node_idxs[k] for k in udeps.through]
    return ParsedDeps(vcat(nodes, groups), cols, through)
end

function parse_once(dp::DepsParser, d::AbstractDict, i::Integer)
    udeps::UnparsedDeps = construct(UnparsedDeps, d)
    pdeps = ParsedDeps(dp, udeps)
    N = length(pdeps.through) + length(pdeps.from)
    append!(dp.srcs, pdeps.through, pdeps.from)
    append!(dp.tgts, StepRangeLen(i, 0, N)) # same as `fill` but does not allocate
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
        group_idxs[k] = i + n_nodes
    end

    dp = DepsParser(node_idxs, group_idxs)

    # This also stores dependency edges in `dp`
    nodes = map(dp, node_configs′, eachindex(node_configs′))
    groups = map(dp, group_configs′, eachindex(group_configs′) .+ n_nodes)

    p = sortperm(dp.srcs)
    G = digraph(view(dp.srcs, p), view(dp.tgts, p), n_nodes + n_groups)

    return G, nodes, groups, collect(String, dp.cols)
end

# Machinery to replace `ParsedDeps`

struct Context
    nodes::Vector{Node}
    outputs::Vector{Vector{String}}
end

# TODO: more general definition
function pass_through(x::AbstractVector, is::AbstractVector, nodes::AbstractVector)
    isempty(is) && return x
    suffix = join((node.card.suffix for node in view(nodes, is)), "_")
    return join_names.(x, suffix)
end

# Nested column computations

function (c::Context)(deps::ParsedDeps)
    nested::Vector{Vector{String}} = vcat(view(c.outputs, deps.from), [deps.cols])
    cols = reduce(vcat, nested)
    return pass_through(cols, deps.through, c.nodes)
end

(c::Context)(d::AbstractDict) = map_into(c, StringDict, d)

function (c::Context)(v::AbstractVector)
    res = Any[]
    for el in v
        # append if `ParsedDeps`, else push
        el isa ParsedDeps ? append!(res, c(el)) : push!(res, c(el))
    end
    return res
end

(_::Context)(x::Any) = x

function Context(G::DiGraph, nodes, groups)
    n_nodes, n_groups = length(nodes), length(groups)
    c = Context(
        Vector{Node}(undef, n_nodes),
        Vector{Vector{String}}(undef, n_nodes + n_groups)
    )
    for i in topological_sort(G)
        if i ≤ n_nodes
            node = Node(c(nodes[i]))
            c.nodes[i] = node
            c.outputs[i] = get_node_outputs(node)
        else
            c.outputs[i] = c(groups[i - n_nodes])
        end
    end
    return c
end
