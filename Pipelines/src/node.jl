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
get_node_outputs(node::Node)::Vector{String} =
    to_outputs(node, output_spec(get_card(node), get_invert(node)))

invertible(n::Node) = invertible(get_card(n))

# set `invert = true`, in which case training is disabled
function invert(n::Node)
    n.invert && throw(ArgumentError("Node is already inverted"))
    return update_node(n; train = false, invert = true)
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
    card, model, state = get_card(node), get_model(node), get_state(node)
    v, state′ = if get_invert(node)
        evaluate(repository, card, model, state, sd, id_var; schema, invert = true)
    else
        evaluate(repository, card, model, state, sd, id_var; schema)
    end
    set_state!(node, state′)
    return v
end

## What a card writes

abstract type AbstractOutputSpec end

"""
    OutputSpec(; names, suffix = nothing, number = nothing)

Columns a card writes under names of its own: each of `names`, followed by `_suffix` when `suffix`
is given, and written `number` times as `_1` … `_number` when `number` is given. These are not
derived from the columns the card was handed, so a `through` chain cannot pass a value through
them.
"""
@defaults struct OutputSpec <: AbstractOutputSpec
    names::Vector{String}
    suffix::Maybe{String} = nothing
    number::Maybe{Int} = nothing
end

get_names(os::OutputSpec) = os.names

"""
    VariableTransformSpec(; cols, suffix = nothing, number = nothing)

Columns a card derives from those it was handed, one for each of `cols`, renamed with `suffix` and
`number` as [`OutputSpec`](@ref) does. A `through` chain can pass a value through it when the
value is among `cols`: the name the chain arrives at is the one this card writes.
"""
@defaults struct VariableTransformSpec <: AbstractOutputSpec
    cols::Vector{String}
    suffix::Maybe{String} = nothing
    number::Maybe{Int} = nothing
end

get_names(vts::VariableTransformSpec) = vts.cols

"""
    OutputGroup(name, spec)

What a card writes, as a specification, under the name a `through` chain or a node selection uses
to ask for it. A named one is a *product*. A card that writes one thing may leave it unnamed; a card
with several names every one, uniquely.
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

A `through` chain asked node `id` to carry `cols`, or a chain or a node selection asked it for a
product, and it cannot.

`allowed` is what the node *can* carry, or `nothing` when nothing passes through it at all — it is
the set an author should be offered instead, which is the difference between a form that proposes a
correction and one that can only refuse. `pointer` addresses the card or group whose chain is at
fault; that is known where the chain is resolved rather than where it fails, so it is filled in
there. `products` is the products the node does name, given when the chain asked for one it does
not have.
"""
struct ThroughError <: Exception
    id::String
    cols::Vector{String}
    allowed::Maybe{Vector{String}}
    reason::Symbol
    products::Vector{String}
    pointer::Maybe{String}
end

function ThroughError(id, cols, allowed, reason; products = String[], pointer = nothing)
    return ThroughError(id, cols, allowed, reason, products, pointer)
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
    elseif err.reason === :no_such_product
        if isempty(err.products)
            print(io, "has no named products, so none can be asked for")
        else
            print(io, "has no such product; it has ", join(err.products, ", "))
        end
    elseif err.reason === :repeated_product
        print(io, "is asked for the same product more than once")
    else
        print(
            io, "does not describe what it writes, so ",
            join(err.cols, ", "), " cannot pass through it"
        )
    end
end

"""
    to_outputs(n::Node, groups, cols, products)::Vector{String}

The names `cols` take after passing through `n`.

`products` is the products the chain asked for by name, or `nothing` for a bare step, which takes
every product able to carry `cols` — one that renames columns it is given, and is given all of
these. Each product chosen is applied to the whole of `cols` in turn.

A chain only means something for a product that derives its outputs from columns it was handed.
One that invents its names refuses, as does a node that declares nothing: the name the chain would
build exists nowhere, and letting it through defers the failure to a task that can name neither the
column nor the node.
"""
function to_outputs(
        n::Node, groups::AbstractVector{OutputGroup},
        cols::AbstractVector{<:AbstractString}, products::Maybe{AbstractVector}
    )
    transforms = [g for g in groups if g.spec isa VariableTransformSpec]
    carries(g) = cols ⊆ g.spec.cols
    accepted(gs) = unique!(foldl(append!, (g.spec.cols for g in gs); init = String[]))

    chosen = if isnothing(products)
        isempty(transforms) && throw(ThroughError(n.id, collect(String, cols), nothing, :names_own_outputs))
        carriers = filter(carries, transforms)
        isempty(carriers) && throw(
            ThroughError(n.id, setdiff(cols, accepted(transforms)), accepted(transforms), :not_carried)
        )
        carriers
    else
        named = named_products(n, groups, products, cols)
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
    return foldl(append!, (to_outputs(g.spec, cols) for g in chosen); init = String[])
end

function to_outputs(n::Node, ::Nothing, cols::AbstractVector{<:AbstractString}, ::Maybe{AbstractVector})
    return throw(ThroughError(n.id, collect(String, cols), nothing, :undeclared))
end

"""
    output_spec(card, invert::Bool)

What `card` writes, as a list of [`OutputGroup`](@ref)s, or `nothing` when it does not declare one.
This is what a card type defines to say what it writes.

A card that cannot be inverted answers the same in both directions, so only an invertible card
needs to look at `invert`.
"""
output_spec(::Card) = nothing

output_spec(c::Card, invert::Bool) = invert ? nothing : output_spec(c)

"""
    named_products(n, groups, products, cols = String[])::Vector{OutputGroup}

The groups of `n` that `products` names, in that order: one lookup for a chain step and a node
selection alike. A name `n` does not write is refused with the ones it does, and so is a name given
twice, which would hand a card the same columns twice. `cols` is what a chain was carrying, so a
refusal can say so; a selection carries nothing.
"""
function named_products(
        n::Node, groups::AbstractVector{OutputGroup}, products::AbstractVector,
        cols::AbstractVector{<:AbstractString} = String[]
    )
    allunique(products) || throw(ThroughError(n.id, collect(String, cols), nothing, :repeated_product))
    names = String[g.name for g in groups if !isnothing(g.name)]
    return map(products) do name
        i = findfirst(g -> g.name == name, groups)
        isnothing(i) && throw(ThroughError(n.id, collect(String, cols), nothing, :no_such_product; products = names))
        groups[i]
    end
end

"""
    narrowed_outputs(n::Node, products)::Vector{String}

The columns `n` writes for the products named, in that order: what a node selection's `products`
keeps of the node.
"""
function narrowed_outputs(n::Node, products::AbstractVector{<:AbstractString})
    groups = output_spec(get_card(n), get_invert(n))
    isnothing(groups) && return to_outputs(n, nothing)   # throws: the card declares nothing
    return foldl(append!, (to_outputs(g.spec) for g in named_products(n, groups, products)); init = String[])
end

"""
    product_outputs(node::Node)

Each product `node` writes, with its columns: what a node selection may narrow it to. Empty for a
card whose one output has no name.
"""
function product_outputs(node::Node)
    groups = output_spec(get_card(node), get_invert(node))
    isnothing(groups) && return NamedTuple[]
    return [(; product = g.name, outputs = to_outputs(g.spec)) for g in groups if !isnothing(g.name)]
end

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
        (; product = g.name, g.spec.cols, g.spec.suffix, g.spec.number)
            for g in groups if g.spec isa VariableTransformSpec
    ]
end

"""
    to_outputs(n::Node, groups)::Vector{String}

Everything `n` writes: each product's outputs, in the order the card declares them.
"""
function to_outputs(::Node, groups::AbstractVector{OutputGroup})
    return foldl(append!, (to_outputs(g.spec) for g in groups); init = String[])
end

# Every card declares what it writes. Reaching this is a card that forgot, and saying so here
# beats its outputs quietly going missing from the pipeline.
function to_outputs(n::Node, ::Nothing)
    return throw(ArgumentError("The card of node `$(n.id)` does not declare what it writes"))
end
