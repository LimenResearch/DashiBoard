mutable struct Node
    const card::Card
    const update::Bool
    const train::Bool
    const invert::Bool
    state::CardState
end

function Node(
        n::Node;
        update::Bool = n.update,
        train::Bool = n.train,
        invert::Bool = n.invert
    )
    (; card, state) = n
    return Node(card, update, train, invert, state)
end

"""
    Node(
        card::Card,
        state = CardState();
        update::Bool = true,
        train::Bool = true,
        invert::Bool = false
    )

Generate a `Node` object from a [`Card`](@ref).
"""
function Node(
        card::Card,
        state = CardState();
        update::Bool = true,
        train::Bool = true,
        invert::Bool = false
    )
    return Node(card, update, train, invert, state)
end

function Node(c::AbstractDict; options...)
    card = Card(c["card"])
    state = CardState(
        content = c["state"]["content"],
        metadata = c["state"]["metadata"]
    )
    return Node(card, state; options...)
end

get_card(node::Node) = node.card
get_update(node::Node) = node.update
get_train(node::Node) = node.train
get_invert(node::Node) = node.invert

get_state(node::Node) = node.state
set_state!(node::Node, state) = setproperty!(node, :state, state)

get_inputs(node::Node) = get_inputs(get_card(node); node.invert, node.train)
get_outputs(node::Node) = get_outputs(get_card(node); node.invert)

invertible(n::Node) = invertible(get_card(n))

invert(n::Node) = invertible(n) ? Node(n, invert = true) : throw(ArgumentError("Node is not invertible"))

"""
    train!(
        repository::Repository,
        node::Node,
        table::AbstractString;
        schema = nothing
    )

Train `node` on table `table` in `repository`.
The field `state` of `node` is modified.

See also [`evaljoin`](@ref), [`train_evaljoin!`](@ref).
"""
function train!(repository::Repository, node::Node, table::AbstractString; schema = nothing)
    get_train(node) || return node
    get_invert(node) && throw(ArgumentError("Cannot train an inverted node"))
    state = train(repository, get_card(node), table; schema)
    set_state!(node, state)
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

"""
    evaljoin!(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString,
        [source_vars];
        schema = nothing
    )

    evaljoin!(
        repository::Repository,
        node::Node,
        tables::Union{AbstractString, Pair},
        [source_vars];
        schema = nothing
    )

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `nodes`, _without training the nodes_.
The resulting outputs of the pipeline are joined with the original columns `source_vars`.

If only a `node` is provided, then it is possible to have distinct source and destination tables.

See also [`train!`](@ref), [`train_evaljoin!`](@ref).

Return pipeline graph and metadata.
"""
function evaljoin end

"""
    train_evaljoin!(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString,
        [source_vars];
        schema = nothing
    )

    train_evaljoin!(
        repository::Repository,
        node::Node,
        tables::Union{AbstractString, Pair},
        [source_vars];
        schema = nothing
    )

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `nodes`, _after having trained the nodes_.
The resulting outputs of the pipeline are joined with the original columns `source_vars`.

If only a `node` is provided, then it is possible to have distinct source and destination tables.

See also [`train!`](@ref), [`evaljoin`](@ref).

Return pipeline graph and metadata.
"""
function train_evaljoin! end

function evaljoin(repository::Repository, node::Node, table_names; schema = nothing)
    evaljoin_many(repository, [node], table_names; schema)
    return
end

function train_evaljoin!(repository::Repository, node::Node, table_names; schema = nothing)
    train_evaljoin_many!(repository, [node], table_names; schema)
    return
end

## Pipeline API

struct Pipeline
    nodes::Vector{Node}
    g::DiGraph{Int}
    source_vars::Vector{String}
    output_vars::Vector{String}
end

function Pipeline(nodes::AbstractVector{Node}, source_vars::AbstractVector{<:AbstractString})
    g, output_vars = digraph_metadata(nodes, source_vars)
    return Pipeline(nodes, g, source_vars, output_vars)
end

function foreach_layer(
        f::F,
        p::Pipeline,
        repository::Repository,
        table::AbstractString;
        schema = nothing
    ) where {F}

    (; nodes, g, source_vars, output_vars) = p
    hs = compute_height(g, nodes)

    # keep original columns if no update is needed, discard everything else
    N, no_update = length(nodes), findall(==(-1), hs)
    keep_vars = (output_vars[idx - N] for i in no_update for idx in outneighbors(g, i))
    q = From(table) |> select_columns(source_vars, keep_vars)
    replace_table(repository, q, table; schema)

    for idxs in layers(hs)
        f(repository, nodes[idxs], table; schema)
    end

    return
end

function evaljoin(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, source_vars = nothing;
        schema = nothing
    )
    source_vars = @something source_vars colnames(repository, table; schema)
    p = Pipeline(Node.(nodes, train = false), source_vars)
    foreach_layer(evaljoin_many, p, repository, table; schema)
    return p.g, p.output_vars
end

function train_evaljoin!(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, source_vars = nothing;
        schema = nothing
    )
    source_vars = @something source_vars colnames(repository, table; schema)
    p = Pipeline(nodes, source_vars)
    foreach_layer(train_evaljoin_many!, p, repository, table; schema)
    return p.g, p.output_vars
end
