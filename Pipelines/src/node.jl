mutable struct StateRef
    state::CardState
end
Base.getindex(ref::StateRef) = getfield(ref, 1)
Base.setindex!(ref::StateRef, state::CardState) = setfield!(ref, 1, state)

struct Node
    card::Card
    update::Bool
    train::Bool
    invert::Bool
    state::StateRef
    function Node(card::Card, update::Bool, train::Bool, invert::Bool, state::StateRef)
        invert && !invertible(card) && throw(ArgumentError("Node is not invertible"))
        return new(card, update, train, invert, state)
    end
end

"""
    Node(
        card::Card,
        state = CardState();
        update::Bool = true,
        train::Bool = true
    )

Generate a `Node` object from a [`Card`](@ref).
"""
function Node(
        card::Card, state::CardState = CardState();
        update::Bool = true, train::Bool = true
    )
    return Node(card, update, train, false, StateRef(state))
end

function Node(c::AbstractDict; update::Bool = true)
    card = Card(c["card"])
    train::Bool = get(c, "train", true)
    state_config = get(c, "state", nothing)
    state = if isnothing(state_config)
        CardState()
    else
        CardState(
            content = c["state"]["content"],
            metadata = c["state"]["metadata"]
        )
    end
    return Node(card, state; update, train)
end

get_card(node::Node) = node.card
get_update(node::Node) = node.update
get_train(node::Node) = node.train
get_invert(node::Node) = node.invert

get_state(node::Node) = node.state[]
set_state!(node::Node, state) = setindex!(node.state, state)

get_inputs(node::Node) = get_inputs(get_card(node); node.invert, node.train)
get_outputs(node::Node) = get_outputs(get_card(node); node.invert)

invertible(n::Node) = invertible(get_card(n))

invert(n::Node) = Node(n.card, n.update, n.train, !n.invert, n.state)
notrain(n::Node) = Node(n.card, n.update, false, n.invert, n.state)
unlink(n::Node) = Node(n.card, n.update, n.train, n.invert, StateRef(get_state(n)))

function check_inverted_no_train(n::Node)
    if get_train(n) && get_invert(n)
        throw(ArgumentError("Cannot train an inverted node"))
    end
    return
end

"""
    train!(
        repository::Repository,
        node::Node,
        table::AbstractString,
        id_var::AbstractString;
        schema = nothing
    )

Train `node` on table `table` in `repository` with primary key `id_var`.
The field `state` of `node` is modified.

See also [`evaljoin`](@ref), [`train_evaljoin!`](@ref).
"""
function train!(
        repository::Repository, node::Node,
        table::AbstractString, id_var::AbstractString;
        schema = nothing
    )
    check_inverted_no_train(node)
    get_train(node) && set_state!(node, train(repository, get_card(node), table, id_var; schema))
    return
end

function evaluate(repository::Repository, node::Node, sd::Pair, id_var::AbstractString; schema = nothing)
    card, state = get_card(node), get_state(node)
    if get_invert(node)
        evaluate(repository, card, state, sd, id_var; schema, invert = true)
    else
        evaluate(repository, card, state, sd, id_var; schema)
    end
    return
end
