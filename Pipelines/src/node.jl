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
get_node_outputs(node::Node)::Vector{String} =
    to_outputs(node, output_spec(get_card(node), get_invert(node)))

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
    OutputGroup(name, spec)

One product of a card: what it writes, as a specification, under the name a `through` chain uses
to ask for it. A card with a single product may leave it unnamed; a card with several names every
one, uniquely.
"""
struct OutputGroup
    name::Maybe{String}
    spec::AbstractOutputSpec
end

OutputGroup(spec::AbstractOutputSpec) = OutputGroup(nothing, spec)

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
there. `groups` is the products the node does name, given when the chain asked for one it does not
have.
"""
struct ThroughError <: Exception
    id::String
    cols::Vector{String}
    allowed::Maybe{Vector{String}}
    reason::Symbol
    groups::Vector{String}
    pointer::Maybe{String}
end

function ThroughError(id, cols, allowed, reason; groups = String[], pointer = nothing)
    return ThroughError(id, cols, allowed, reason, groups, pointer)
end

function Base.showerror(io::IO, err::ThroughError)
    print(io, "Node `", err.id, "` ")
    return if err.reason === :not_carried
        print(io, "does not read ", join(err.cols, ", "), "; it reads ", join(err.allowed, ", "))
    elseif err.reason === :names_own_outputs
        print(
            io, "writes columns of its own rather than renaming what it is given, so ",
            join(err.cols, ", "), " cannot pass through it"
        )
    elseif err.reason === :no_such_group
        if isempty(err.groups)
            print(io, "has no named products, so a chain cannot ask for one")
        else
            print(io, "has no such product; it has ", join(err.groups, ", "))
        end
    elseif err.reason === :repeated_group
        print(io, "is asked for the same product more than once")
    else
        print(
            io, "does not describe what it writes, so ",
            join(err.cols, ", "), " cannot pass through it"
        )
    end
end

"""
    to_outputs(n::Node, groups, cols, wanted)::Vector{String}

The names `cols` take after passing through `n`.

`wanted` is the products the chain asked for by name, or `nothing` for a bare step, which takes
every product able to carry `cols` — one that renames columns it is given, and is given all of
these. Each product chosen is applied to the whole of `cols` in turn.

A chain only means something for a product that derives its outputs from columns it was handed.
One that invents its names refuses, as does a node that declares nothing: the name the chain would
build exists nowhere, and letting it through defers the failure to a task that can name neither the
column nor the node.
"""
function to_outputs(
        n::Node, groups::AbstractVector{OutputGroup},
        cols::AbstractVector{<:AbstractString}, wanted::Maybe{AbstractVector}
    )
    transforms = [g for g in groups if g.spec isa VariableTransformSpec]
    carries(g) = cols ⊆ g.spec.cols
    accepted(gs) = unique!(reduce(vcat, (g.spec.cols for g in gs); init = String[]))

    chosen = if isnothing(wanted)
        isempty(transforms) && throw(ThroughError(n.id, collect(String, cols), nothing, :names_own_outputs))
        carriers = filter(carries, transforms)
        isempty(carriers) && throw(
            ThroughError(n.id, setdiff(cols, accepted(transforms)), accepted(transforms), :not_carried)
        )
        carriers
    else
        allunique(wanted) || throw(ThroughError(n.id, collect(String, cols), nothing, :repeated_group))
        names = String[g.name for g in groups if !isnothing(g.name)]
        named = map(wanted) do name
            i = findfirst(g -> g.name == name, groups)
            isnothing(i) && throw(ThroughError(n.id, collect(String, cols), nothing, :no_such_group; groups = names))
            groups[i]
        end
        # All or nothing: a step is refused rather than narrowed to the products that can carry it.
        for g in named
            g.spec isa VariableTransformSpec ||
                throw(ThroughError(n.id, collect(String, cols), nothing, :names_own_outputs))
        end
        all(carries, named) || throw(
            ThroughError(n.id, setdiff(cols, accepted(named)), accepted(named), :not_carried)
        )
        named
    end
    return reduce(vcat, (to_outputs(g.spec, cols) for g in chosen); init = String[])
end

function to_outputs(n::Node, ::Nothing, cols::AbstractVector{<:AbstractString}, ::Maybe{AbstractVector})
    return throw(ThroughError(n.id, collect(String, cols), nothing, :undeclared))
end

"""
    output_spec(card, invert::Bool)

What `card` writes, as a list of [`OutputGroup`](@ref)s, or `nothing` when it does not declare one.

Only an invertible card answers differently in the two directions, and only `RescaleCard` is
invertible, so every other card ignores `invert`.
"""
output_spec(::Card) = nothing

output_spec(c::Card, invert::Bool) = invert ? nothing : output_spec(c)

"""
    through_options(node::Node)

How a value may pass through `node`: one entry per product that renames what it is given, in the
order the card declares them, naming the columns it accepts and the rule that renames them. Empty
when nothing can pass through.
"""
function through_options(node::Node)
    groups = output_spec(get_card(node), get_invert(node))
    isnothing(groups) && return NamedTuple[]
    return [
        (; group = g.name, g.spec.cols, g.spec.suffix, g.spec.number)
            for g in groups if g.spec isa VariableTransformSpec
    ]
end

"""
    to_outputs(n::Node, groups)::Vector{String}

Everything `n` writes: each product's outputs, in the order the card declares them.
"""
function to_outputs(::Node, groups::AbstractVector{OutputGroup})
    return reduce(vcat, (to_outputs(g.spec) for g in groups); init = String[])
end

# Every card declares what it writes. Reaching this is a card that forgot, and saying so here
# beats its outputs quietly going missing from the pipeline.
function to_outputs(n::Node, ::Nothing)
    return throw(ArgumentError("The card of node `$(n.id)` does not declare what it writes"))
end
