mutable struct Node
    const card::Union{AbstractCard, Nothing}
    const inputs::OrderedSet{String}
    const outputs::OrderedSet{String}
    update::Bool
    model::Any
end

function Node(card::AbstractCard, update::Bool)
    return Node(
        card,
        inputs(card),
        outputs(card),
        update,
        nothing
    )
end

get_update(node::Node) = node.update
set_update!(node::Node, update::Bool) = setproperty!(node, :update, update)

get_model(node::Node) = node.model
set_model!(node::Node, m) = setproperty!(node, :model, m)

get_card(node::Node) = node.card

function digraph(nodes)
    N = length(nodes)
    g = DiGraph(N)

    for (i, n) in enumerate(nodes)
        for (i′, n′) in enumerate(nodes)
            isdisjoint(n.outputs, n′.inputs) || add_edge!(g, i => i′)
        end
    end

    return g
end

# Compute order and `update` property
function evaluation_order!(nodes::AbstractVector{Node})
    order = Int[]
    g = digraph(nodes)
    for idx in topological_sort(g)
        n, ns = nodes[idx], view(nodes, inneighbors(g, idx))
        if get_update(n) || any(get_update, ns)
            set_update!(n, true)
            push!(order, idx)
        end
    end
    return order
end

const CARD_TYPES = Dict(
    "split" => SplitCard,
    "rescale" => RescaleCard,
    "glm" => GLMCard,
    "interp" => InterpCard,
    "gaussian_encoding" => GaussianEncodingCard
)

"""
    get_card(d::AbstractDict)

Generate an [`AbstractCard`](@ref) based on a configuration dictionary.
"""
function get_card(d::AbstractDict)
    sd = Dict(Symbol(k) => v for (k, v) in pairs(d))
    type = pop!(sd, :type)
    return CARD_TYPES[type](; sd...)
end

"""
    evaluate(repo::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)

Replace `table` in the database `repo.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repo::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards, true)
    if any(get_update, nodes)
        order = evaluation_order!(nodes)
        for idx in order
            node = nodes[idx]
            m = evaluate(repo, node.card, table => table; schema)
            set_model!(node, m)
            set_update!(node, false)
        end
    end
    return nodes
end

# TODO: similar method for `deevaluate`?
# TODO: `deevaluate(repo, node.card, node.model, source => target; schema)`

_union!(s::AbstractSet{<:AbstractString}, x::AbstractString) = push!(s, x)
_union!(s::AbstractSet{<:AbstractString}, x::AbstractVector) = union!(s, x)
_union!(s::AbstractSet{<:AbstractString}, ::Nothing) = s

stringset!(s::AbstractSet{<:AbstractString}, args...) = (foreach(Fix1(_union!, s), args); s)

stringset(args...) = stringset!(OrderedSet{String}(), args...)

# Note: for the moment this evaluates the nodes in order 
function deevaluate(repo::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        deevaluate(repo, node.card, node.model, table => table; schema)
    end
end

filter_partition(partition::AbstractString, n::Integer = 1) = Where(Get(partition) .== n)

function filter_partition(::Nothing, n::Integer = 1)
    if n != 1
        throw(ArgumentError("Data has not been split"))
    end
    return identity
end

function card_configurations(;
        rescale = (;),
        split = (;),
        glm = (;),
        interp = (;),
    )

    return [
        CardWidget(SplitCard; split...),
        CardWidget(RescaleCard; rescale...),
        CardWidget(GLMCard; glm...),
        CardWidget(InterpCard; interp...),
    ]
end
