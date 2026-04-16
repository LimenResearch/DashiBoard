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
        f::F, repository::Repository, p::Pipeline,
        tbl::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing, options...
    ) where {F}

    (; nodes, layers) = p

    for idxs in layers
        f(repository, nodes[idxs], tbl, id_var; schema, options...)
    end

    return p
end

## Parallel computations

function train_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        tbl::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        train_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )
    n = length(nodes)
    Threads.foreach(to_channel(1:n); ntasks) do i
        node = nodes[i]
        train!(repository, node, tbl, id_var; schema)
        train_callback(node)
    end
    return
end

function _evaljoin(
        repository::Repository, node::Node, (src, dst)::Pair,
        tmp_name::AbstractString, id_var::AbstractString,
        lock::Union{AbstractLock, Nothing} = nothing;
        schema::Union{AbstractString, Nothing} = nothing
    )
    input, output = get_inputs(node), get_outputs(node)
    vars = colnames(repository, src; schema)
    if !issubset(input, vars) || !in(id_var, vars)
        @show id_var
        @show input
        @show vars
        throw(ArgumentError("Column not found"))
    end
    evaluate(repository, notrain(node), src => tmp_name, id_var; schema)
    if isnothing(lock)
        join_on_id_var(repository, dst, tmp_name, id_var, output; schema)
    else
        @lock lock join_on_id_var(repository, dst, tmp_name, id_var, output; schema)
    end
    return id_var, output
end

function evaljoin_many(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        tbl::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )
    n = length(nodes)
    lock = ReentrantLock()

    with_table_names(repository, n; schema) do tmp_names
        Threads.foreach(to_channel(1:n); ntasks) do i
            node, tmp_name = nodes[i], tmp_names[i]
            _, output = _evaljoin(repository, node, tbl => tbl, tmp_name, id_var, lock; schema)
            eval_callback(node, output)
        end
    end

    return
end

function train_evaljoin_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        tbl::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        train_callback = Returns(nothing), eval_callback = Returns(nothing),
        ntasks::Integer = Threads.threadpoolsize()
    )
    train_many!(repository, nodes, tbl, id_var; schema, train_callback, ntasks)
    evaljoin_many(repository, nodes, tbl, id_var; schema, eval_callback, ntasks)
    return
end

## Training and evaluation methods

"""
    evaljoin(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
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
If a list of nodes is provided, return pipeline graph and metadata.

See also [`train!`](@ref), [`train_evaljoin!`](@ref).
"""
function evaljoin end

"""
    train_evaljoin!(
        repository::Repository,
        nodes::AbstractVector,
        table::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
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
If a list of nodes is provided, return pipeline graph and metadata.

See also [`train!`](@ref), [`evaljoin`](@ref).
"""
function train_evaljoin! end

function evaljoin(
        repository::Repository, node::Node, (src, dst)::Pair, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )
    # TODO: we might wish to make this step customizable
    replace_table(repository, From(src), dst; schema)
    with_table_name(repository; schema) do tmp_name
        _evaljoin(repository, node, src => dst, tmp_name, id_var; schema)
    end
    return
end

function evaljoin(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing, options...
    )
    p = Pipeline(nodes, train = false)
    return evaljoin(repository, p, table, id_var; schema, options...)
end

function evaljoin(
        repository::Repository, p::Pipeline,
        table::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing, options...
    )
    # TODO: here and in `train_evaljoin!` consider different scheduling
    return foreach_layer(evaljoin_many, repository, p, table, id_var; schema, options...)
end

function train_evaljoin!(
        repository::Repository, node::Node,
        (src, dst)::Pair, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )
    train!(repository, node, src, id_var; schema)
    evaljoin(repository, node, src => dst, id_var; schema)
    return
end

function train_evaljoin!(
        repository::Repository, nodes::AbstractVector{Node},
        table::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing, options...
    )
    p = Pipeline(nodes, train = true)
    return train_evaljoin!(repository, p, table, id_var; schema, options...)
end

function train_evaljoin!(
        repository::Repository, p::Pipeline,
        table::AbstractString, id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing, options...
    )
    return foreach_layer(train_evaljoin_many!, repository, p, table, id_var; schema, options...)
end
