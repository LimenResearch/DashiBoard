mutable struct Node
    const card::Union{AbstractCard, Nothing}
    const inputs::OrderedSet{String}
    const outputs::OrderedSet{String}
    update::Bool
    state::CardState
end

function Node(card::AbstractCard, update::Bool)
    return Node(
        card,
        inputs(card),
        outputs(card),
        update,
        CardState()
    )
end

# TODO: test constructor
function Node(config::AbstractDict, update::Bool)
    card = get_card(config[:card])
    node = Node(card, update)
    state = CardState(
        content = config[:state][:content],
        metadata = config[:state][:metadata]
    )
    set_state!(node, state)
    return node
end

get_update(node::Node) = node.update
set_update!(node::Node, update::Bool) = setproperty!(node, :update, update)

get_state(node::Node) = node.state
set_state!(node::Node, state) = setproperty!(node, :state, state)

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
    "gaussian_encoding" => GaussianEncodingCard,
    "streamliner" => StreamlinerCard,
)

"""
    get_card(d::AbstractDict)

Generate an [`AbstractCard`](@ref) based on a configuration dictionary.
"""
function get_card(d::AbstractDict)
    c = to_config(d)
    type = pop!(c, :type)
    return CARD_TYPES[type](c)
end

"""
    evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards, true)
    if any(get_update, nodes)
        order = evaluation_order!(nodes)
        for idx in order
            node = nodes[idx]
            state = evaluate(repository, node.card, table => table; schema)
            set_state!(node, state)
            set_update!(node, false)
        end
    end
    return nodes
end

_union!(s::AbstractSet{<:AbstractString}, x::AbstractString) = push!(s, x)
_union!(s::AbstractSet{<:AbstractString}, x::AbstractVector) = union!(s, x)
_union!(s::AbstractSet{<:AbstractString}, ::Nothing) = s

stringset!(s::AbstractSet{<:AbstractString}, args...) = (foreach(Fix1(_union!, s), args); s)

stringset(args...) = stringset!(OrderedSet{String}(), args...)

# Note: for the moment this evaluates the nodes in order
# TODO: finalize (de)evaluatenodes interface

# pass `nodes = Node.(Config.(configs), true)` as argument
function evaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        evaluate(repository, node.card, node.state, table => table; schema)
    end
    return
end

function deevaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        deevaluate(repository, node.card, node.state, table => table; schema)
    end
    return
end

filter_partition(partition::AbstractString, n::Integer = 1) = Where(Get(partition) .== n)

function filter_partition(::Nothing, n::Integer = 1)
    if n != 1
        throw(ArgumentError("Data has not been split"))
    end
    return identity
end

function check_order(c::AbstractDict)
    order_by = get(c, :order_by, String[])
    if isempty(order_by)
        throw(
            ArgumentError(
                """
                At least one sorter is required.
                """
            )
        )
    end
end

function card_widget(d::AbstractDict, key::AbstractString; kwargs...)
    return @with WIDGET_CONFIG => merge(d["general"], d[key]) begin
        card = CARD_TYPES[key]
        CardWidget(card; kwargs...)
    end
end

# FIXME: add StreamlinerCard
function card_configurations(;
        split = (;),
        rescale = (;),
        glm = (;),
        interp = (;),
        gaussian_encoding = (;),
        streamliner = (;),
    )

    d = Dict(
        "general" => parsefile(config_path("general.toml")),
        "split" => parsefile(config_path("split.toml")),
        "rescale" => parsefile(config_path("rescale.toml")),
        "glm" => parsefile(config_path("glm.toml")),
        "interp" => parsefile(config_path("interp.toml")),
        "gaussian_encoding" => parsefile(config_path("gaussian_encoding.toml")),
        "streamliner" => parsefile(config_path("streamliner.toml")),
    )

    return [
        card_widget(d, "split"; split...),
        card_widget(d, "rescale"; rescale...),
        card_widget(d, "glm"; glm...),
        card_widget(d, "interp"; interp...),
        card_widget(d, "gaussian_encoding"; gaussian_encoding...),
        card_widget(d, "streamliner"; streamliner...),
    ]
end
