mutable struct StateRef
    model::Any
    state::Any
end

StateRef() = StateRef(nothing, nothing)

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
        state::StateRef = StateRef(get_model(n), get_state(n)) # avoid linking
    )

    return Node(card, id, update, train, invert, label, state)
end

"""
    Node(
        card::Card, state::StateRef = StateRef();
        id::AbstractString = "",
        update::Bool = true, train::Bool = true,
        label::AbstractString = get_default_label(card)
    )

Generate a `Node` object from a [`Card`](@ref).
"""
function Node(
        card::Card, state::StateRef = StateRef();
        id::AbstractString = "",
        update::Bool = true, train::Bool = true,
        label::AbstractString = get_default_label(card)
    )
    return Node(card, id, update, train, false, label, state)
end

get_id(d::AbstractDict)::String = get(d, "id", "")

function Node(d::AbstractDict; update::Bool = true)
    card = Card(d["card"])
    id::String = get_id(d)
    label::String = get(() -> get_default_label(card), d, "label")
    train::Bool = get(d, "train", true)
    return Node(card; id, update, train, label)
end

get_card(node::Node) = node.card
get_update(node::Node) = node.update
get_train(node::Node) = node.train
get_invert(node::Node) = node.invert
get_label(node::Node) = node.label

get_model(node::Node) = node.state.model
set_model!(node::Node, model) = (node.state.model = model; node)

get_state(node::Node) = node.state.state
set_state!(node::Node, state) = (node.state.state = state; node)

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

function regularize(v::AbstractVector)::Tuple{Vector{String}, Nothing}
    cols::Vector{String} = v
    return cols, nothing
end

function regularize((v, s)::Tuple{<:AbstractVector, T})::Tuple{Vector{String}, T} where {T}
    cols::Vector{String} = v
    return cols, s
end

function with_state!(n::Node, v)
    cols, state = regularize(v)
    set_state!(n, state)
    return cols
end

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
        schema::Maybe{AbstractString} = nothing
    )
    get_train(node) && set_model!(node, train(repository, get_card(node), table, id_var; schema))
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
        schema::Maybe{AbstractString} = nothing
    )
    card, model = get_card(node), get_model(node)
    res = if get_invert(node)
        evaluate(repository, card, model, sd, id_var; schema, invert = true)
    else
        evaluate(repository, card, model, sd, id_var; schema)
    end
    return with_state!(node, res)
end
