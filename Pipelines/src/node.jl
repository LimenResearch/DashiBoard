mutable struct StateRef
    state::CardState
end
Base.getindex(ref::StateRef) = getfield(ref, 1)
Base.setindex!(ref::StateRef, state::CardState) = setfield!(ref, 1, state)

struct Node
    card::Card
    id::String
    update::Bool
    train::Bool
    invert::Bool
    label::String
    state::StateRef
    function Node(
            card::Card,
            id::AbstractString,
            update::Bool,
            train::Bool,
            invert::Bool,
            label::AbstractString,
            state::StateRef,
        )
        if invert
            invertible(card) || throw(ArgumentError("Card `$(card)` is not invertible"))
            train && throw(ArgumentError("Cannot train an inverted node"))
        end
        return new(card, id, update, train, invert, label, state)
    end
end

function update_node(
        n::Node;
        card::Card = n.card,
        id::AbstractString = n.id,
        update::Bool = n.update,
        train::Bool = n.train,
        invert::Bool = n.invert,
        label::AbstractString = n.label,
        state::StateRef = n.state
    )

    return Node(card, id, update, train, invert, label, state)
end

"""
    Node(
        card::Card, state = CardState();
        id::AbstractString = "",
        update::Bool = true, train::Bool = true,
        label::AbstractString = get_default_label(card)
    )

Generate a `Node` object from a [`Card`](@ref).
"""
function Node(
        card::Card, state::CardState = CardState();
        id::AbstractString = "",
        update::Bool = true, train::Bool = true,
        label::AbstractString = get_default_label(card)
    )
    return Node(card, id, update, train, false, label, StateRef(state))
end

get_id(d::AbstractDict)::String = get(d, "id", "")

function Node(d::AbstractDict; update::Bool = true)
    card = Card(d["card"])
    id::String = get_id(d)
    label::String = get(() -> get_default_label(card), d, "label")
    train::Bool = get(d, "train", true)
    state_config = get(d, "state", nothing)
    state = if isnothing(state_config)
        CardState()
    else
        CardState(
            content = d["state"]["content"],
            metadata = d["state"]["metadata"]
        )
    end
    return Node(card, state; id, update, train, label)
end

get_card(node::Node) = node.card
get_update(node::Node) = node.update
get_train(node::Node) = node.train
get_invert(node::Node) = node.invert
get_label(node::Node) = node.label

get_state(node::Node) = node.state[]
set_state!(node::Node, state) = setindex!(node.state, state)

"""
    get_node_inputs(node::Node)::Vector{String}

Return the lists of variables required in input for a given `node`.
"""
function get_node_inputs(node::Node)::Vector{String}
    c, invert, train = get_card(node), get_invert(node), get_train(node)
    vars = SourceVariables(c)
    always_include = (vars.order_by, vars.group_by, vars.helpers)
    return if invert
        union(always_include..., vars.inverse_inputs)
    elseif train
        union(
            always_include...,
            vars.inputs,
            vars.targets,
            to_stringlist(vars.weights),
            to_stringlist(vars.partition),
        )
    else
        union(always_include..., vars.inputs)
    end
end

"""
    get_node_outputs(node::Node)::Vector{String}

Return the lists of variables produced as output by a given `node`.
"""
function get_node_outputs(node::Node)::Vector{String}
    c, invert = get_card(node), get_invert(node)
    vars = OutputVariables(c)
    return invert ? vars.inverse_outputs : vars.outputs
end

invertible(n::Node) = invertible(get_card(n))

# set `invert = true`, in which case training is disabled
function invert(n::Node)
    n.invert && throw(ArgumentError("Node is already inverted"))
    return update_node(n; train = false, invert = true)
end

unlink(n::Node) = update_node(n; state = StateRef(get_state(n)))

"""
    train!(
        repository::Repository,
        node::Node,
        table::AbstractString,
        id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )

Train `node` on table `table` in `repository` with primary key `id_var`.
The field `state` of `node` is modified.

See also [`evaljoin`](@ref), [`train_evaljoin!`](@ref).
"""
function train!(
        repository::Repository, node::Node,
        table::AbstractString, id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    get_train(node) && set_state!(node, train(repository, get_card(node), table, id_var; schema))
    return
end

"""
    evaluate(
        repository::Repository, node::Node,
        (source, destination)::Pair, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )

Evaluate the card corresponding to a given `node` (using the node's state)
on table `source` with primary column `id_var`.
Then save the output in table `destination`.

A card that rolls its state forward as it evaluates may return
`(columns, state)` instead of `columns`; the new state is then stored in the
node. See `_persist_state!`.
"""
function evaluate(
        repository::Repository, node::Node,
        sd::Pair, id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    card, state = get_card(node), get_state(node)
    result = if get_invert(node)
        evaluate(repository, card, state, sd, id_var; schema, invert = true)
    else
        evaluate(repository, card, state, sd, id_var; schema)
    end
    return _persist_state!(node, result)
end

"""
    _persist_state!(node::Node, result)

Unwrap what a card's `evaluate` returned. Cards return their output columns and
this passes them through untouched; a card that also rolls its state forward
returns `(columns, state)`, and that state is stored in `node`.

The pass-through is untyped because it must accept whatever any card returns.
The tuple method is typed exactly, since the only cards producing one are those
opting into this behaviour: `CardState` is what [`set_state!`](@ref) can store,
and `Vector{String}` is the column contract `evaljoin` relies on. Anything else
— including a tuple of other types — falls through to the pass-through rather
than being mistaken for a state update.
"""
_persist_state!(::Node, result) = result

function _persist_state!(node::Node, (columns, state)::Tuple{Vector{String}, CardState})
    set_state!(node, state)
    return columns
end
