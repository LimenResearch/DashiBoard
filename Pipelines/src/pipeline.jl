mutable struct Node
    const card::Union{Card, Nothing}
    const inputs::OrderedSet{String}
    const outputs::OrderedSet{String}
    const update::Bool
    state::CardState
end

function Node(card::Card, update::Bool = true)
    return Node(
        card,
        inputs(card),
        outputs(card),
        update,
        CardState()
    )
end

function Node(c::AbstractDict, update::Bool = true)
    card = Card(c["card"])
    node = Node(card, update)
    state = CardState(
        content = c["state"]["content"],
        metadata = c["state"]["metadata"]
    )
    set_state!(node, state)
    return node
end

get_card(node::Node) = node.card
get_inputs(node::Node) = node.inputs
get_outputs(node::Node) = node.outputs
get_update(node::Node) = node.update

get_state(node::Node) = node.state
set_state!(node::Node, state) = setproperty!(node, :state, state)

inputs(nodes::AbstractVector{Node}) = mapfoldl(get_inputs, union!, nodes, init = stringset())
outputs(nodes::AbstractVector{Node}) = mapfoldl(get_outputs, union!, nodes, init = stringset())

function evaluate!(repository::Repository, nodes::AbstractVector{Node}, table::AbstractString; schema = nothing)
    ns = colnames(repository, table; schema)
    diff = setdiff(inputs(nodes), ns ∪ outputs(nodes))
    if !isempty(diff)
        throw(ArgumentError("Variables $(collect(diff)) where not found in the data."))
    end

    hs = compute_height(nodes)
    for idxs in layers(hs)
        # TODO: this can be run in parallel (cards must be made thread-safe first)
        for idx in idxs
            node = nodes[idx]
            card = get_card(node)
            state = evaluate(repository, card, table => table; schema)
            set_state!(node, state)
        end
    end

    return nodes
end

"""
    evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards)
    return evaluate!(repository, nodes, table; schema)
end

# Note: for the moment this evaluates the nodes in order
# TODO: finalize (de)evaluatenodes interface

# pass `nodes = Node.(configs)` as argument
function evaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        evaluate(repository, get_card(node), get_state(node), table => table; schema)
    end
    return
end

function deevaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        deevaluate(repository, get_card(node), get_state(node), table => table; schema)
    end
    return
end
