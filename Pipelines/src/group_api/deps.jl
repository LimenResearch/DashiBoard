# utils

@defaults struct DepsParser
    node_idxs::Dict{String, Int}
    group_idxs::Dict{String, Int}
    srcs::Vector{Int} = Int[]
    tgts::Vector{Int} = Int[]
    cols::OrderedSet{String} = OrderedSet{String}()
end

function append_edges!(dp::DepsParser, srcs::AbstractVector, dst::Integer)
    append!(dp.srcs, srcs)
    # here, `StepRangeLen` is the same as `fill` but does not allocate
    append!(dp.tgts, StepRangeLen(dst, 0, length(srcs)))
    return dp
end

const DEPS_NAMES = Set{String}(("nodes", "groups", "cols", "through"))

is_deps(d::AbstractDict) = keys(d) ⊆ DEPS_NAMES && count(!=("through"), keys(d)) == 1

struct Source
    cols::Vector{String}
end

struct Computed
    idxs::Vector{Int}
end

struct Deps
    inputs::Union{Source, Computed}
    through::Vector{Int}
end

function Deps(dp::DepsParser, d::AbstractDict)
    k::String = only(Iterators.filter(!=("through"), keys(d)))
    v::Vector{String} = d[k]
    idx_dict = k == "nodes" ? dp.node_idxs : k == "groups" ? dp.group_idxs : nothing
    inputs = isnothing(idx_dict) ? Source(v) : Computed(Int[idx_dict[k] for k in v])
    through::Vector{String} = get(d, "through", String[])
    through_idxs = Int[dp.node_idxs[k] for k in through]
    return Deps(inputs, through_idxs)
end

update!(dp::DepsParser, inputs::Computed, dst::Integer) = append_edges!(dp, inputs.idxs, dst)
update!(dp::DepsParser, inputs::Source, _::Integer) = (union!(dp.cols, inputs.cols); dp)

function parse_once(dp::DepsParser, d::AbstractDict, i::Integer)
    deps = Deps(dp, d)
    append_edges!(dp, deps.through, i)
    update!(dp, deps.inputs, i)
    return deps
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

# Machinery to replace `Deps`

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

get_cols(::Context, inputs::Source)::Vector{String} = inputs.cols
get_cols(c::Context, inputs::Computed)::Vector{String} = reduce(vcat, view(c.outputs, inputs.idxs))

(c::Context)(deps::Deps) = pass_through(get_cols(c, deps.inputs), deps.through, c.nodes)

(c::Context)(d::AbstractDict) = map_into(c, StringDict, d)

function (c::Context)(v::AbstractVector)
    res = Any[]
    for el in v
        # append if `Deps`, else push
        el isa Deps ? append!(res, c(el)) : push!(res, c(el))
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
