mutable struct Node
    const card::Card
    const update::Bool
    state::CardState
end

Node(card::Card, update::Bool = true) = Node(card, update, CardState())

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
get_update(node::Node) = node.update

get_state(node::Node) = node.state
set_state!(node::Node, state) = setproperty!(node, :state, state)

get_inputs(node::Node)::Vector{String} = get_inputs(get_card(node))
get_outputs(node::Node)::Vector{String} = get_outputs(get_card(node))

function evaluate!(repository::Repository, nodes::AbstractVector{Node}, table::AbstractString; schema = nothing)
    ns = colnames(repository, table; schema)
    g, output_vars = digraph_metadata(nodes, ns)
    hs = compute_height(g, nodes)
    for idxs in layers(hs)
        # TODO: this can be run in parallel (cards must be made thread-safe first)
        for idx in idxs
            node = nodes[idx]
            card = get_card(node)
            state = evaluate(repository, card, table => table; schema)
            set_state!(node, state)
        end
    end

    return g, output_vars
end

"""
    evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards)
    evaluate!(repository, nodes, table; schema)
    return nodes
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
