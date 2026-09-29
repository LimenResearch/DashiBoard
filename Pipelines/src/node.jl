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
get_node_outputs(node::Node)::Vector{String} = to_outputs(node, output_spec(get_card(node)))

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
        schema::Maybe{AbstractString} = nothing
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
        schema::Maybe{AbstractString} = nothing
    )
    card, state = get_card(node), get_state(node)
    return if get_invert(node)
        evaluate(repository, card, state, sd, id_var; schema, invert = true)
    else
        evaluate(repository, card, state, sd, id_var; schema)
    end
end

## Output transformation (consider adding inside `CardSpec`)

abstract type AbstractOutputSpec end

@defaults struct OutputSpec <: AbstractOutputSpec
    names::Vector{String} # could be `OrderedSet{String}` as an optimization
    suffix::Maybe{String} = nothing
    number::Maybe{Int} = nothing
end

get_names(os::OutputSpec) = os.names

@defaults struct VariableTransformSpec <: AbstractOutputSpec
    cols::Vector{String} # could be `OrderedSet{String}` as an optimization
    suffix::Maybe{String} = nothing
    number::Maybe{Int} = nothing
end

get_names(vts::VariableTransformSpec) = vts.cols

"""
    InvertibleSpec(forward, inverse_outputs)

Outputs for a card that runs both ways: `forward` transforms the columns it is given, while the
inverse writes `inverse_outputs` whatever it is handed. The inverse is a plain list because undoing
a transformation is not itself one — it strips a suffix rather than appending one — so no
`VariableTransformSpec` describes it.

Answers `to_outputs` only when given a node: without the direction the question has no single
answer.
"""
@defaults struct InvertibleSpec <: AbstractOutputSpec
    forward::VariableTransformSpec
    inverse_outputs::Vector{String} = String[]
end

function _to_outputs(
        names::AbstractVector{<:AbstractString},
        suffix::Maybe{AbstractString},
        number::Maybe{<:Integer}
    )::Vector{String}
    args = isnothing(suffix) ? (names,) : (names, suffix)
    return isnothing(number) ? join_names.(args...) : vec(join_names.(args..., (1:number)'))
end

"""
    to_outputs(os::AbstractOutputSpec, names = get_names(os))::Vector{String}

The column names a card declaring `os` writes. Pass `names` to ask the same of a subset — what a
`through` chain carrying part of a node's vocabulary comes out as.
"""
function to_outputs(os::AbstractOutputSpec, names::AbstractVector{<:AbstractString} = get_names(os))
    (; suffix, number) = os
    return _to_outputs(names, suffix, number)
end

"""
    ThroughError(id, cols, allowed, reason, pointer = nothing)

A `through` chain asked node `id` to carry `cols`, and it cannot.

`allowed` is what the node *can* carry, or `nothing` when nothing passes through it at all — it is
the set an author should be offered instead, which is the difference between a form that proposes a
correction and one that can only refuse. `pointer` addresses the card or group whose chain is at
fault; that is known where the chain is resolved rather than where it fails, so it is filled in
there.
"""
struct ThroughError <: Exception
    id::String
    cols::Vector{String}
    allowed::Maybe{Vector{String}}
    reason::Symbol
    pointer::Maybe{String}
end

ThroughError(id, cols, allowed, reason) = ThroughError(id, cols, allowed, reason, nothing)

function Base.showerror(io::IO, err::ThroughError)
    print(io, "Node `", err.id, "` ")
    return if err.reason === :not_carried
        print(io, "does not read ", join(err.cols, ", "), "; it reads ", join(err.allowed, ", "))
    elseif err.reason === :names_own_outputs
        print(io, "names its own outputs, so nothing can pass through it")
    elseif err.reason === :undeclared
        print(io, "does not declare what it produces, so nothing can pass through it")
    else
        print(io, "undoes a transformation, so nothing can pass through it")
    end
end

"""
    to_outputs(n::Node, spec, cols)::Vector{String}

The names `cols` take after passing through `n`.

A chain only means something for a node that derives its outputs from columns it was handed. A node
that invents its outputs, that undoes a transformation, or that declares nothing refuses: the name
the chain would build exists nowhere, and letting it through defers the failure to a task that can
name neither the column nor the node.
"""
function to_outputs(n::Node, v::VariableTransformSpec, cols::AbstractVector{<:AbstractString})
    extras = setdiff(cols, v.cols)
    isempty(extras) || throw(ThroughError(n.id, extras, v.cols, :not_carried))
    return to_outputs(v, cols)
end

function to_outputs(n::Node, ::OutputSpec, cols::AbstractVector{<:AbstractString})
    return throw(ThroughError(n.id, collect(String, cols), nothing, :names_own_outputs))
end

function to_outputs(n::Node, ::Nothing, cols::AbstractVector{<:AbstractString})
    return throw(ThroughError(n.id, collect(String, cols), nothing, :undeclared))
end

function to_outputs(n::Node, s::InvertibleSpec, cols::AbstractVector{<:AbstractString})
    get_invert(n) && throw(ThroughError(n.id, collect(String, cols), nothing, :inverted))
    return to_outputs(n, s.forward, cols)
end

output_spec(::Card) = nothing

"""
    to_outputs(n::Node, spec)::Vector{String}

What `n` writes. Most specifications answer the same whichever way a node runs, so the node is
only consulted for the ones that do not.
"""
to_outputs(::Node, os::AbstractOutputSpec) = to_outputs(os)

to_outputs(n::Node, s::InvertibleSpec) = get_invert(n) ? s.inverse_outputs : to_outputs(s.forward)

# A card that has not declared a specification answers the old way. This method is the whole of
# what is left to migrate: when every card declares one, it goes, and `OutputVariables` stops
# being reachable from here.
function to_outputs(n::Node, ::Nothing)
    vars = OutputVariables(get_card(n))
    return get_invert(n) ? vars.inverse_outputs : vars.outputs
end
