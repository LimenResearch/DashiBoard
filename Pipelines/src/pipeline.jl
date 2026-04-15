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

function get_outputs(p::Pipeline, i::Integer)
    (; g, output_vars) = p.enriched_digraph
    return output_vars[outneighbors(g, i) .- length(p.nodes)]
end

graphviz(io::IO, p::Pipeline) = graphviz(io, p.enriched_digraph, p.nodes)

function foreach_layer(
        f::F, repository::Repository, p::Pipeline, table::AbstractString;
        schema = nothing, options...
    ) where {F}

    (; nodes, layers) = p

    for idxs in layers
        f(repository, nodes[idxs], table; schema, options...)
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
        repository::Repository, nodes::Union{Tuple, AbstractVector}, tbl::AbstractString;
        schema = nothing, eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )
    n = length(nodes)
    outputs = get_outputs.(nodes)
    id_vars = new_name.("id", outputs)
    l = ReentrantLock()

    with_table_names(repository, n; schema) do tmp_names
        Threads.foreach(to_channel(1:n); ntasks) do i
            node, tmp_name, id_var, output = nodes[i], tmp_names[i], id_vars[i], outputs[i]
            try
                evaluate(repository, node, tbl => tmp_name, id_var; schema)
                q = join_on_row_number(tbl, tmp_name, id_var, output)
                @lock l replace_table(repository, q, tbl; schema)
                eval_callback(node)
            finally
                @lock l delete_table(repository, tmp_name)
            end
        end
    end

    return
end

function train_evaljoin_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector}, tbl::AbstractString;
        schema = nothing, train_callback = Returns(nothing), eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )
    train_many!(repository, nodes, tbl; schema, train_callback, ntasks)
    evaljoin_many(repository, nodes, tbl; schema, eval_callback, ntasks)
    return
end

## Training and evaluation methods

"""
    evaljoin(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString;
        schema = nothing,
        eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )

    evaljoin(
        repository::Repository,
        node::Node,
        (source, destination)::Pair;
        schema = nothing
    )

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `nodes`, _without training the nodes_.
The resulting outputs of the pipeline are joined with the original columns.

If only a `node` is provided, then one should pass both source and destination tables.

See also [`train!`](@ref), [`train_evaljoin!`](@ref).

Return pipeline graph and metadata.
"""
function evaljoin end

"""
    train_evaljoin!(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString;
        schema = nothing,
        train_callback = Returns(nothing),
        eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )

    train_evaljoin!(
        repository::Repository,
        node::Node,
        (source, destination)::Pair;
        schema = nothing
    )

Replace `table` in the database `repository.db` with the outcome of executing all
the transformations in `nodes`, _after having trained the nodes_.
The resulting outputs of the pipeline are joined with the original columns.

If only a `node` is provided, then one should pass both source and destination tables.

See also [`train!`](@ref), [`evaljoin`](@ref).

Return pipeline graph and metadata.
"""
function train_evaljoin! end

function evaljoin(
        repository::Repository, node::Node, (src, dst)::Pair; schema = nothing
    )
    with_table_name(repository; schema) do tmp_name
        output = get_outputs(node)
        id_var = new_name("id", output)
        evaluate(repository, notrain(node), src => tmp_name, id_var; schema)
        q = join_on_row_number(src, tmp_name, id_var, output)
        replace_table(repository, q, dst; schema)
    end
    return
end

function evaljoin(
        repository::Repository, nodes::AbstractVector{Node}, table::AbstractString;
        schema = nothing, options...
    )
    p = Pipeline(nodes, train = false)
    return evaljoin(repository, p, table; schema, options...)
end

function evaljoin(
        repository::Repository, p::Pipeline, table::AbstractString;
        schema = nothing, options...
    )
    # TODO: here and in `train_evaljoin!` consider different scheduling
    return foreach_layer(evaljoin_many, repository, p, table; schema, options...)
end

function train_evaljoin!(
        repository::Repository, node::Node, (src, dst)::Pair; schema = nothing
    )
    train!(repository, node, src; schema)
    evaljoin(repository, node, src => dst; schema)
    return
end

function train_evaljoin!(
        repository::Repository, nodes::AbstractVector{Node}, table::AbstractString;
        schema = nothing, options...
    )
    p = Pipeline(nodes, train = true)
    return train_evaljoin!(repository, p, table; schema, options...)
end

function train_evaljoin!(
        repository::Repository, p::Pipeline, table::AbstractString;
        schema = nothing, options...
    )
    return foreach_layer(train_evaljoin_many!, repository, p, table; schema, options...)
end
