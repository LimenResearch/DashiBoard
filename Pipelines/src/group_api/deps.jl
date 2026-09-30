# utils

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

@defaults struct DepsParser
    node_idxs::Dict{String, Int}
    group_idxs::Dict{String, Int}
    srcs::Vector{Int} = Int[]
    tgts::Vector{Int} = Int[]
    cols::OrderedSet{String} = OrderedSet{String}()
end

function append_edges!(dp::DepsParser, src::AbstractVector, dst::Integer)
    append!(dp.srcs, src)
    # here, `StepRangeLen` is the same as `fill` but does not allocate
    append!(dp.tgts, StepRangeLen(dst, 0, length(src)))
    return dp
end

update!(dp::DepsParser, src::Computed, dst::Integer) = append_edges!(dp, src.idxs, dst)
update!(dp::DepsParser, src::Source, _::Integer) = (union!(dp.cols, src.cols); dp)

# Parsing machinery

const DEPS_NAMES = Set{String}(("nodes", "groups", "cols", "through"))

not_through(s) = !isequal(s, "through")
get_through(d::AbstractDict)::Vector{String} = get(d, "through", String[])

is_deps(d::AbstractDict) = keys(d) ⊆ DEPS_NAMES && count(not_through, keys(d)) == 1

function Deps(dp::DepsParser, d::AbstractDict, i::Integer)
    key::String = only(Iterators.filter(not_through, keys(d)))
    val::Vector{String} = to_stringlist(d[key])
    idx_dict = key == "nodes" ? dp.node_idxs : key == "groups" ? dp.group_idxs : nothing
    inputs = isnothing(idx_dict) ? Source(val) : Computed(Int[idx_dict[k] for k in val])
    through = Int[dp.node_idxs[k] for k in get_through(d)]

    update!(dp, inputs, i)
    append_edges!(dp, through, i)

    return Deps(inputs, through)
end

function (dp::DepsParser)(d::AbstractDict, i::Integer)
    return is_deps(d) ? Deps(dp, d, i) : map_into(Fix2(dp, i), StringDict, d)
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
    group_names = Vector{String}(undef, n_groups)
    for (i, (k, grp)) in enumerate(pairs(group_configs))
        group_configs′[i] = grp isa AbstractVector ? grp : Any[grp]
        group_names[i] = k
    end
    group_idxs = Dict{String, Int}(zip(group_names, eachindex(group_names) .+ n_nodes))

    dp = DepsParser(node_idxs, group_idxs)

    # This also stores dependency edges in `dp`
    nodes = map(dp, node_configs′, eachindex(node_configs′))
    groups = map(dp, group_configs′, eachindex(group_configs′) .+ n_nodes)

    p = sortperm(dp.srcs)
    G = digraph(view(dp.srcs, p), view(dp.tgts, p), n_nodes + n_groups)

    # `group_names` is returned to clarify the iteration order used to generate `groups`.
    return G, nodes, group_names => groups, collect(String, dp.cols)
end

# Machinery to replace `Deps`

struct Context
    nodes::Vector{Node}
    outputs::Vector{Vector{String}}
end

# Fold the chain: each node renames what the one before it handed on, and refuses a value it does
# not transform. This is what makes a `through` list checkable rather than a name built on hope.
function pass_through(x::AbstractVector, is::AbstractVector, nodes::AbstractVector)
    for i in is
        node = nodes[i]
        x = to_outputs(node, output_spec(get_card(node), get_invert(node)), x)
    end
    return x
end

# Nested column computations

get_cols(::Context, inputs::Source) = inputs.cols
get_cols(c::Context, inputs::Computed) = reduce(vcat, view(c.outputs, inputs.idxs))
get_cols(c::Context, deps::Deps) = pass_through(get_cols(c, deps.inputs), deps.through, c.nodes)

# consider allowing `get_cols` to return `0` items, in which case return `nothing`
(c::Context)(deps::Deps) = only(get_cols(c, deps))
(c::Context)(d::AbstractDict) = map_into(c, StringDict, d)

function (c::Context)(v::AbstractVector)
    res = Any[]
    for el in v
        # append if `Deps`, else push
        el isa Deps ? append!(res, get_cols(c, el)) : push!(res, c(el))
    end
    return res
end

(_::Context)(x::Any) = x

# A `through` failure knows which node refused but not which card or group asked it to, since it is
# raised where the chain is walked. This is the frame that knows. Everything else passes untouched,
# backtrace included.
function at_pointer(f::F, pointer::AbstractString) where {F}
    return try
        f()
    catch err
        err isa ThroughError || rethrow()
        throw(ThroughError(err.id, err.cols, err.allowed, err.reason, pointer))
    end
end

function Context(G::DiGraph, nodes, groups, group_names)
    n_nodes, n_groups = length(nodes), length(groups)
    c = Context(
        Vector{Node}(undef, n_nodes),
        Vector{Vector{String}}(undef, n_nodes + n_groups)
    )
    for i in topological_sort(G)
        if i ≤ n_nodes
            node = at_pointer("/nodes/$(i - 1)/card") do
                Node(c(nodes[i]))
            end
            c.nodes[i] = node
            c.outputs[i] = get_node_outputs(node)
        else
            name = group_names[i - n_nodes]
            c.outputs[i] = at_pointer("/groups/" * escape_pointer(name)) do
                c(groups[i - n_nodes])
            end
        end
    end
    return c
end
