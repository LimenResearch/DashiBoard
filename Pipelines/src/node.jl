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
    label::String
    state::StateRef
    function Node(
            card::Card,
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
        return new(card, update, train, invert, label, state)
    end
end

function update_node(
        n::Node;
        card::Card = n.card,
        update::Bool = n.update,
        train::Bool = n.train,
        invert::Bool = n.invert,
        label::AbstractString = n.label,
        state::StateRef = n.state
    )

    return Node(card, update, train, invert, label, state)
end

"""
    Node(
        card::Card, state = CardState();
        update::Bool = true, train::Bool = true,
        label::AbstractString = ""
    )

Generate a `Node` object from a [`Card`](@ref).
"""
function Node(
        card::Card, state::CardState = CardState();
        update::Bool = true, train::Bool = true,
        label::AbstractString = ""
    )
    return Node(card, update, train, false, label, StateRef(state))
end

function Node(d::AbstractDict; update::Bool = true, adjust::Bool = false)
    card = Card(d["card"]; adjust)
    label::String = get(d, "label", "")
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
    return Node(card, state; update, train, label)
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
"""
function evaluate(
        repository::Repository, node::Node,
        sd::Pair, id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    card, state = get_card(node), get_state(node)
    return if get_invert(node)
        evaluate(repository, card, state, sd, id_var; schema, invert = true)
    else
        evaluate(repository, card, state, sd, id_var; schema)
    end
end
