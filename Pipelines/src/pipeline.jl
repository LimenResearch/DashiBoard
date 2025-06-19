mutable struct Node
    const card::Union{Card, Nothing}
    const inputs::OrderedSet{String}
    const outputs::OrderedSet{String}
    update::Bool
    state::CardState
end

function Node(card::Card, update::Bool = true)
    return Node(
        card,
        inputs(card),
        outputs(card),
        update,
        CardState()
    )
end

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

get_update(node::Node) = node.update
set_update!(node::Node, update::Bool) = setproperty!(node, :update, update)

get_state(node::Node) = node.state
set_state!(node::Node, state) = setproperty!(node, :state, state)

get_card(node::Node) = node.card
get_inputs(node::Node) = node.inputs
get_outputs(node::Node) = node.outputs

function required_inputs(nodes::AbstractVector{Node})
    res = stringset()
    mapfoldl(get_inputs, union!, nodes, init = res)
    mapfoldl(get_outputs, setdiff!, nodes, init = res)
    return res
end

is_input_of(src::Node, tgt::Node) = !isdisjoint(src.outputs, tgt.inputs)

function adjacency_matrix(nodes::AbstractVector{Node})
    N = length(nodes)
    M = spzeros(Bool, N, N)
    M .= is_input_of.(nodes, permutedims(nodes))
    return M
end

digraph(nodes::AbstractVector{Node}) = DiGraph(adjacency_matrix(nodes))

function node_parents_dict(nodes::AbstractVector{Node}, g::DiGraph)
    order = topological_sort(g)
    return OrderedDict(nodes[i] => view(nodes, inneighbors(g, i)) for i in order)
end

function evaluate!(repository::Repository, nodes::AbstractVector{Node}, table::AbstractString; schema = nothing)
    g = digraph(nodes)

    if is_cyclic(g)
        throw(ArgumentError("Cyclic dependency found!"))
    end

    vars = required_inputs(nodes)
    ns = colnames(repository, table; schema)
    if vars ⊈ ns
        diff = join(setdiff(vars, ns), ", ")
        throw(ArgumentError("Variables $(diff) where not found in the data."))
    end

    d = node_parents_dict(nodes, g)
    for (node, parents) in pairs(d)
        if get_update(node) || any(get_update, parents)
            state = evaluate(repository, get_card(node), table => table; schema)
            set_state!(node, state)
            set_update!(node, true)
        end
    end

    return nodes
end

"""
    evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `cards`.
"""
function evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = Node.(cards)
    return evaluate!(repository, nodes, table; schema)
end

# Note: for the moment this evaluates the nodes in order
# TODO: finalize (de)evaluatenodes interface

# pass `nodes = Node.(configs)` as argument
function evaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        evaluate(repository, get_card(node), get_state(node), table => table; schema)
    end
    return
end

function deevaluatenodes(repository::Repository, nodes::AbstractVector, table::AbstractString; schema = nothing)
    for node in nodes
        deevaluate(repository, get_card(node), get_state(node), table => table; schema)
    end
    return
end
