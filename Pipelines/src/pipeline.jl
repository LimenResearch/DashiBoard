## Pipeline API

struct Pipeline
    nodes::Vector{Node}
    enriched_digraph::EnrichedDiGraph{Int}
    precomputed_nodes::Vector{Int}
    layers::Vector{Vector{Int}}
end

function Pipeline(node_iter; train::Bool = true)
    nodes::Vector{Node} = train ? collect(Node, node_iter) : map(notrain, node_iter)
    foreach(check_inverted_no_train, nodes)
    enriched_digraph = EnrichedDiGraph(nodes)
    hs = compute_height(enriched_digraph.g, get_update.(nodes))
    precomputed_nodes = findall(==(-1), hs)
    return Pipeline(
        nodes,
        enriched_digraph,
        precomputed_nodes,
        layers(hs)
    )
end

no_update_vars(p::Pipeline) = Iterators.flatmap(Fix1(get_outputs, p), p.precomputed_nodes)

function get_outputs(p::Pipeline, i::Integer)
    (; g, output_vars) = p.enriched_digraph
    return output_vars[outneighbors(g, i) .- length(p.nodes)]
end

graphviz(io::IO, p::Pipeline) = graphviz(io, p.enriched_digraph, p.nodes)

function foreach_layer(
        f::F,
        repository::Repository,
        p::Pipeline,
        table::AbstractString,
        keep_vars::Union{AbstractVector, Nothing};
        schema = nothing
    ) where {F}

    keep_vars = @something keep_vars colnames(repository, table; schema)
    (; g, source_vars, output_vars) = p.enriched_digraph
    (; nodes, layers) = p

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
    evaljoin(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString,
        [keep_vars];
        schema = nothing
    )

    evaljoin(
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
