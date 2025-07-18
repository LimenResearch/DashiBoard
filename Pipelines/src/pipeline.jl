const StateRef = Base.RefValue{CardState}

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
        update::Bool = true
    )

Generate a `Node` object from a [`Card`](@ref).
"""
function Node(card::Card, state::CardState = CardState(); update::Bool = true)
    train, invert = true, false
    return Node(card, update, train, invert, StateRef(state))
end

function Node(c::AbstractDict; update::Bool = true)
    card = Card(c["card"])
    state = CardState(
        content = c["state"]["content"],
        metadata = c["state"]["metadata"]
    )
    return Node(card, state; update)
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
        table::AbstractString;
        schema = nothing
    )

Train `node` on table `table` in `repository`.
The field `state` of `node` is modified.

See also [`evaljoin`](@ref), [`train_evaljoin!`](@ref).
"""
function train!(repository::Repository, node::Node, table::AbstractString; schema = nothing)
    check_inverted_no_train(node)
    get_train(node) && set_state!(node, train(repository, get_card(node), table; schema))
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

## Pipeline API

struct Pipeline
    nodes::Vector{Node}
    g::DiGraph{Int}
    precomputed_nodes::Vector{Int}
    layers::Vector{Vector{Int}}
    source_vars::Vector{String}
    output_vars::Vector{String}
end

function Pipeline(node_iter; train::Bool = true)
    nodes::Vector{Node} = train ? collect(Node, node_iter) : map(notrain, node_iter)
    foreach(check_inverted_no_train, nodes)
    g, source_vars, output_vars = digraph_metadata(nodes)
    hs = compute_height(g, get_update.(nodes))
    precomputed_nodes = findall(==(-1), hs)
    return Pipeline(
        nodes,
        g,
        precomputed_nodes,
        layers(hs),
        source_vars,
        output_vars
    )
end

no_update_vars(p::Pipeline) = Iterators.flatmap(Fix1(get_outputs, p), p.precomputed_nodes)

get_outputs(p::Pipeline, i::Integer) = p.output_vars[outneighbors(p.g, i) .- length(p.nodes)]

graphviz(io::IO, p::Pipeline) = graphviz(io, p.g, p.nodes, p.output_vars)

function foreach_layer(
        f::F,
        repository::Repository,
        p::Pipeline,
        table::AbstractString,
        keep_vars::Union{AbstractVector, Nothing};
        schema = nothing
    ) where {F}

    keep_vars = @something keep_vars colnames(repository, table; schema)
    (; nodes, g, layers, source_vars, output_vars) = p

    # Keep columns if any of the following condition applies:
    # - they belong to `keep_vars`,
    # - they are the input of a node,
    # - they are the output of a precomputed node.
    q = From(table) |> select_columns(keep_vars, source_vars, no_update_vars(p))
    replace_table(repository, q, table; schema)

    for idxs in layers
        f(repository, nodes[idxs], table => table; schema)
    end

    return p
end

## Parallel computations

function train_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        table::AbstractString; schema = nothing
    )
    n = length(nodes)
    Threads.@threads for i in 1:n
        train!(repository, nodes[i], table; schema)
    end
    return
end

function evaljoin_many(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        (source, destination)::Pair; schema = nothing
    )
    n = length(nodes)
    outputs = get_outputs.(nodes)
    tmp_names = join_names.(string(uuid4()), 1:n)
    id_vars = new_name.("id", outputs)

    try
        Threads.@threads for i in 1:n
            evaluate(repository, nodes[i], source => tmp_names[i], id_vars[i]; schema)
        end
        q = join_on_row_number(source, tmp_names, id_vars, outputs)
        replace_table(repository, q, destination; schema)
    finally
        for tmp in tmp_names
            delete_table(repository, tmp; schema)
        end
    end
    return
end

function train_evaljoin_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        (source, destination)::Pair; schema = nothing
    )
    train_many!(repository, nodes, source; schema)
    evaljoin_many(repository, nodes, source => destination; schema)
    return
end

## Training and evaluation methods

"""
    evaljoin!(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString,
        [keep_vars];
        schema = nothing
    )

    evaljoin!(
        repository::Repository,
        node::Node,
        (source, destination)::Pair,
        [keep_vars];
        schema = nothing
    )

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `nodes`, _without training the nodes_.
The resulting outputs of the pipeline are joined with the original columns `keep_vars`
(defaults to keeping all columns).

If only a `node` is provided, then one should pass both source and destination tables.

See also [`train!`](@ref), [`train_evaljoin!`](@ref).

Return pipeline graph and metadata.
"""
function evaljoin end

"""
    train_evaljoin!(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString,
        [keep_vars];
        schema = nothing
    )

    train_evaljoin!(
        repository::Repository,
        node::Node,
        (source, destination)::Pair,
        [keep_vars];
        schema = nothing
    )

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `nodes`, _after having trained the nodes_.
The resulting outputs of the pipeline are joined with the original columns `keep_vars`
(defaults to keeping all columns).

If only a `node` is provided, then one should pass both source and destination tables.

See also [`train!`](@ref), [`evaljoin`](@ref).

Return pipeline graph and metadata.
"""
function train_evaljoin! end

function evaljoin(
        repository::Repository, node::Node,
        table_names::Pair; schema = nothing
    )
    evaljoin_many(repository, (node,), table_names; schema)
    return
end

function evaljoin(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, keep_vars::Union{AbstractVector, Nothing} = nothing;
        schema = nothing
    )
    p = Pipeline(nodes, train = false)
    return evaljoin(repository, p, table, keep_vars; schema)
end

function evaljoin(
        repository::Repository, p::Pipeline,
        table::AbstractString, keep_vars::Union{AbstractVector, Nothing} = nothing;
        schema = nothing
    )
    return foreach_layer(evaljoin_many, repository, p, table, keep_vars; schema)
end

function train_evaljoin!(
        repository::Repository, node::Node,
        table_names::Pair; schema = nothing
    )
    train_evaljoin_many!(repository, (node,), table_names; schema)
    return
end

function train_evaljoin!(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, keep_vars::Union{AbstractVector, Nothing} = nothing;
        schema = nothing
    )
    p = Pipeline(nodes, train = true)
    return train_evaljoin!(repository, p, table, keep_vars; schema)
end

function train_evaljoin!(
        repository::Repository, p::Pipeline,
        table::AbstractString, keep_vars::Union{AbstractString, Nothing} = nothing;
        schema = nothing
    )
    return foreach_layer(train_evaljoin_many!, repository, p, table, keep_vars; schema)
end
