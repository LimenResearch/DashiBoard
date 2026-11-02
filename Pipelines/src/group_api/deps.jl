# utils

struct Cols
    cols::Vector{String}
end

struct Groups
    groups::Vector{Int}
end

# The node, and the products of it the chain asked for by name —
# or `nothing`, which takes every product.
struct SubNode
    node::Int
    products::Maybe{Vector{String}}
end

get_node_idx(s::SubNode) = s.node

struct Nodes
    nodes::Vector{SubNode}
end

struct Deps
    inputs::Union{Nodes, Groups, Cols}
    through::Vector{SubNode}
end

@defaults struct DepsParser
    node_idxs::Dict{String, Int}
    group_idxs::Dict{String, Int}
    srcs::Vector{Int} = Int[]
    tgts::Vector{Int} = Int[]
    cols::OrderedSet{String} = OrderedSet{String}()
end

Broadcast.broadcastable(dp::DepsParser) = Ref(dp)

node_idx(dp::DepsParser, k::AbstractString) = dp.node_idxs[k]
group_idx(dp::DepsParser, k::AbstractString) = dp.group_idxs[k]

SubNode(dp::DepsParser, id::AbstractString) = SubNode(node_idx(dp, id), nothing)
SubNode(dp::DepsParser, d::AbstractDict) = SubNode(node_idx(dp, d["node"]), d["products"])

function append_edges!(dp::DepsParser, src::AbstractVector, dst::Integer)
    append!(dp.srcs, src)
    # here, `StepRangeLen` is the same as `fill` but does not allocate
    append!(dp.tgts, StepRangeLen(dst, 0, length(src)))
    return dp
end

update!(dp::DepsParser, src::Nodes, dst::Integer) = append_edges!(dp, get_node_idx.(src.nodes), dst)
update!(dp::DepsParser, src::Groups, dst::Integer) = append_edges!(dp, src.groups, dst)
update!(dp::DepsParser, src::Cols, _::Integer) = (union!(dp.cols, src.cols); dp)

# Parsing machinery

# Exactly one of these says what is selected; `through` qualifies it.
const DEPS_KINDS = ("nodes", "groups", "cols")

get_through(d::AbstractDict)::Vector{Any} = get(d, "through", Any[])

is_deps(d::AbstractDict) = keys(d) ⊆ (DEPS_KINDS..., "through") && count(in(DEPS_KINDS), keys(d)) == 1

function Deps(dp::DepsParser, d::AbstractDict, i::Integer)
    key::String = only(Iterators.filter(in(DEPS_KINDS), keys(d)))
    inputs = if key == "nodes"
        nodes::Vector{Any} = to_list(Any, d[key])
        Nodes(SubNode.(dp, nodes))
    elseif key == "groups"
        groups::Vector{String} = to_stringlist(d[key])
        Groups(group_idx.(dp, groups))
    else # cols
        cols::Vector{String} = to_stringlist(d[key])
        Cols(cols)
    end
    through::Vector{SubNode} = SubNode.(dp, get_through(d))

    update!(dp, inputs, i)
    append_edges!(dp, get_node_idx.(through), i)

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

# Fold the chain: each node renames what the one before it handed on, through the products the
# step asked for, and refuses a value they do not transform. This is what makes a `through` list
# checkable rather than a name built on hope.
function pass_through(cols::AbstractVector, steps::AbstractVector{SubNode}, nodes::AbstractVector)
    return foldl(steps, init = cols) do x, step
        node = nodes[get_node_idx(step)]
        to_outputs(node, output_spec(node), x, step.products)
    end
end

# Nested column computations

get_cols(::Context, inputs::Cols) = inputs.cols
get_cols(c::Context, inputs::Groups) = reduce(vcat, view(c.outputs, inputs.groups))
function get_cols(c::Context, inputs::Nodes)
    return flat_stringlist(s -> narrowed_outputs(c.nodes[s.node], s.products), inputs.nodes)
end
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

with_pointer(err::ThroughError, pointer::AbstractString) =
    ThroughError(err.id, err.cols, err.allowed, err.reason, err.products, pointer)
# A product refusal is about one field of the card, so it is addressed one step further in.
with_pointer(err::ProductError, pointer::AbstractString) =
    ProductError(err.message, err.field, string(pointer, '/', err.field))

# A transform refusal is raised by the funnel, which knows the entry but not the card it sits in.
function with_pointer(err::SC.TransformError, pointer::AbstractString)
    entry = join(Iterators.map(escape_pointer, err.path), '/')
    return SC.TransformError(err.message, err.path, string(pointer, "/funnel/", entry))
end

# A `through` failure knows which node refused but not which card or group asked it to, since it is
# raised where the chain is walked; a product refusal knows the field but not the card. This is
# the frame that knows. Everything else passes untouched, backtrace included.
function at_pointer(f::F, pointer::AbstractString) where {F}
    return try
        f()
    catch err
        err isa Union{ThroughError, ProductError, SC.TransformError} || rethrow()
        throw(with_pointer(err, pointer))
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
            # Naming the outputs is where a card's product selection is checked, so it is done
            # inside the frame that knows which card this is.
            c.nodes[i], c.outputs[i] = at_pointer("/nodes/$(i - 1)/card") do
                node = Node(c(nodes[i]))
                node, get_node_outputs(node)
            end
        else
            name = group_names[i - n_nodes]
            c.outputs[i] = at_pointer("/groups/" * escape_pointer(name)) do
                c(groups[i - n_nodes])
            end
        end
    end
    return c
end
