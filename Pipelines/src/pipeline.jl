mutable struct Node
    const card::Card
    const update::Bool
    state::CardState
end

Node(n::Node) = Node(n.card, n.update, n.state)

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

function evaluate!(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString; schema = nothing, invert = false
    )
    source_vars = colnames(repository, table; schema)
    return evaluate!(repository, nodes, table, source_vars; schema, invert, update = true)
end

function evaluate!(
        repository::Repository,
        nodes::AbstractVector{Node},
        table::AbstractString,
        source_vars::AbstractVector;
        schema = nothing,
        invert = false,
        update = true
    )

    g, output_vars = digraph_metadata(nodes, source_vars; invert)
    hs = compute_height(g, nodes)

    # keep original columns if no update is needed, discard everything else
    N, no_update = length(nodes), findall(==(-1), hs)
    keep_vars = (output_vars[idx - N] for i in no_update for idx in outneighbors(g, i))
    q = From(table) |> select_columns(source_vars, keep_vars)
    replace_table(repository, q, table; schema)

    for idxs in layers(hs)
        layer_nodes = nodes[idxs]
        layer_cards = get_card.(layer_nodes)
        if update
            invert && throw(ArgumentError("`update = true` not allowed in invert mode"))
            layer_states = evaluate_many(repository, layer_cards, table => table; schema)
            foreach(set_state!, layer_nodes, layer_states)
        else
            layer_states = get_state.(layer_nodes)
            evaluate_many(repository, layer_cards, layer_states, table => table; schema, invert)
        end
    end

    return g, output_vars
end

"""
    evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing, invert = false)

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing, invert = false)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards)
    evaluate!(repository, nodes, table; schema, invert)
    return nodes
end
