mutable struct Node
    const card::Union{AbstractCard, Nothing}
    const inputs::OrderedSet{String}
    const outputs::OrderedSet{String}
    update::Bool
    state::CardState
end

function Node(card::AbstractCard, update::Bool = true)
    return Node(
        card,
        inputs(card),
        outputs(card),
        update,
        CardState()
    )
end

function Node(d::AbstractDict, update::Bool = true)
    config = to_config(d)
    card = get_card(config[:card])
    node = Node(card, update)
    state = CardState(
        content = config[:state][:content],
        metadata = config[:state][:metadata]
    )
    set_state!(node, state)
    return node
end

get_update(node::Node) = node.update
set_update!(node::Node, update::Bool) = setproperty!(node, :update, update)

get_state(node::Node) = node.state
set_state!(node::Node, state) = setproperty!(node, :state, state)

get_card(node::Node) = node.card

function digraph(nodes)
    N = length(nodes)
    g = DiGraph(N)

    for (i, n) in enumerate(nodes)
        for (i′, n′) in enumerate(nodes)
            isdisjoint(n.outputs, n′.inputs) || add_edge!(g, i => i′)
        end
    end

    return g
end

# Compute order and `update` property
function evaluation_order!(nodes::AbstractVector{Node})
    order = Int[]
    g = digraph(nodes)
    for idx in topological_sort(g)
        n, ns = nodes[idx], view(nodes, inneighbors(g, idx))
        if get_update(n) || any(get_update, ns)
            set_update!(n, true)
            push!(order, idx)
        end
    end
    return order
end

"""
    evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards)
    if any(get_update, nodes)
        order = evaluation_order!(nodes)
        for idx in order
            node = nodes[idx]
            state = evaluate(repository, node.card, table => table; schema)
            set_state!(node, state)
            set_update!(node, false)
        end
    end
    return nodes
end

# Note: for the moment this evaluates the nodes in order
# TODO: finalize (de)evaluatenodes interface

# pass `nodes = Node.(configs)` as argument
function evaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        evaluate(repository, node.card, node.state, table => table; schema)
    end
    return
end

function deevaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        deevaluate(repository, node.card, node.state, table => table; schema)
    end
    return
end
