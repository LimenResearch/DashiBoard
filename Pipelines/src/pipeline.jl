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
        schema = nothing,
        options...
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
        f(repository, nodes[idxs], table => table; schema, options...)
    end

    return p
end

## Parallel computations

function train_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector}, table::AbstractString;
        schema = nothing, train_callback = Returns(nothing), ntasks::Integer = Threads.threadpoolsize()
    )
    n = length(nodes)
    Threads.foreach(to_channel(1:n); ntasks) do i
        node = nodes[i]
        train!(repository, node, table; schema)
        train_callback(node)
    end
    return
end

function evaljoin_many(
        repository::Repository, nodes::Union{Tuple, AbstractVector}, (source, destination)::Pair;
        schema = nothing, eval_callback = Returns(nothing), ntasks::Integer = Threads.threadpoolsize()
    )
    n = length(nodes)
    outputs = get_outputs.(nodes)
    id_vars = new_name.("id", outputs)

    with_table_names(repository, n; schema) do tmp_names
        try
            Threads.foreach(to_channel(1:n); ntasks) do i
                node, tmp_name, id_var = nodes[i], tmp_names[i], id_vars[i]
                evaluate(repository, node, source => tmp_name, id_var; schema)
                eval_callback(node, tmp_name)
            end
            q = join_on_row_number(source, tmp_names, id_vars, outputs)
            replace_table(repository, q, destination; schema)
        finally
            for tmp in tmp_names
                delete_table(repository, tmp; schema)
            end
        end
    end
    return
end

function train_evaljoin_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector}, (source, destination)::Pair;
        schema = nothing, train_callback = Returns(nothing), eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )
    train_many!(repository, nodes, source; schema, train_callback, ntasks)
    evaljoin_many(repository, nodes, source => destination; schema, eval_callback, ntasks)
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
        repository::Repository, node::Node, table_names::Pair;
        schema = nothing, options...
    )
    evaljoin_many(repository, (node,), table_names; schema, options...)
    return
end

function evaljoin(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, keep_vars::Union{AbstractVector, Nothing} = nothing;
        schema = nothing, options...
    )
    p = Pipeline(nodes, train = false)
    return evaljoin(repository, p, table, keep_vars; schema, options...)
end

function evaljoin(
        repository::Repository, p::Pipeline,
        table::AbstractString, keep_vars::Union{AbstractVector, Nothing} = nothing;
        schema = nothing, options...
    )
    # TODO: here and in `train_evaljoin!` consider different scheduling
    return foreach_layer(evaljoin_many, repository, p, table, keep_vars; schema, options...)
end

function train_evaljoin!(
        repository::Repository, node::Node, table_names::Pair;
        schema = nothing, options...
    )
    train_evaljoin_many!(repository, (node,), table_names; schema, options...)
    return
end

function train_evaljoin!(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, keep_vars::Union{AbstractVector, Nothing} = nothing;
        schema = nothing, options...
    )
    p = Pipeline(nodes, train = true)
    return train_evaljoin!(repository, p, table, keep_vars; schema, options...)
end

function train_evaljoin!(
        repository::Repository, p::Pipeline,
        table::AbstractString, keep_vars::Union{AbstractString, Nothing} = nothing;
        schema = nothing, options...
    )
    return foreach_layer(train_evaljoin_many!, repository, p, table, keep_vars; schema, options...)
end
