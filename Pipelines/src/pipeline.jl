mutable struct Node
    const inputs::Set{String}
    const outputs::Set{String}
    update::Bool
end

function Node(inputs::AbstractVector, outputs::AbstractVector, update::Bool)
    return Node(Set{String}(inputs), Set{String}(outputs), update)
end

get_update(node::Node) = node.update
set_update!(node::Node, update::Bool) = setproperty!(node, :update, update)

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

const CARD_TYPES = Dict(
    "tiled_partition" => TiledPartition,
    "percentile_partition" => PercentilePartition,
)

get_card(d::AbstractDict) = CARD_TYPES[d["type"]](d)
get_card(c::AbstractCard) = c

struct Cards
    cards::Vector{AbstractCard}
    function Cards(cs::AbstractVector)
        cards::Vector{AbstractCard} = get_card.(cs)
        return new(cards)
    end
end

function evaluate(
        cards::Cards,
        repo::Repository,
        table::AbstractString
    )
    # For now, we update all the nodes TODO: mark which cards need updating
    nodes = [Node(inputs(card), outputs(card), true) for card in cards.cards]
    order = evaluation_order!(nodes)
    for idx in order
        evaluate(cards.cards[idx], repo, table => table)
    end
end
