abstract type ClusteringMethod end

@kwarg struct KMeansMethod <: ClusteringMethod
    classes::Int & (dashi = StringDict("minimum" => 1),)
    iterations::Int = 100 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
    seed::Union{Int, Nothing} = nothing & (dashi = StringDict("minimum" => 0),)
end

function (m::KMeansMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    return kmeans(X, classes; maxiter = iterations, tol, rng = get_rng(seed), weights)
end

@kwarg struct DBSCANMethod <: ClusteringMethod
    radius::Float64 & (dashi = StringDict("exclusiveMinimum" => 0),)
    min_neighbors::Int = 1 & (dashi = StringDict("minimum" => 1),)
    min_cluster_size::Int = 1 & (dashi = StringDict("minimum" => 1),)
end

function (m::DBSCANMethod)(X; weights)
    (; radius, min_neighbors, min_cluster_size) = m
    isnothing(weights) || @warn "Weights not supported in DBSCAN"
    return dbscan(X, radius; min_neighbors, min_cluster_size)
end

const CLUSTERING_METHODS = OrderedDict{String, DataType}(
    "kmeans" => KMeansMethod,
    "dbscan" => DBSCANMethod,
)

# TODO: support custom metrics
"""
    struct ClusterCard <: Card
        type::String
        method::String
        clusterer::ClusteringMethod
        inputs::Vector{String}
        assign_inputs::Union{Vector{String}, Nothing}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        output::String
    end

Cluster `inputs` based on `clusterer`.
Save resulting column as `output`.

For the `kmeans` method, evaluation assigns each row to the nearest fitted
centroid, so a trained card can label rows outside the training set. `assign_inputs`
(a subset of `inputs`, defaulting to all of them) selects which dimensions the
assignment distance uses — e.g. cluster on space and time but assign on space only.
Ignored by `dbscan`, which has no predict and re-emits the training-row labels.
"""
struct ClusterCard <: StandardCard
    type::String
    method::String
    clusterer::ClusteringMethod
    inputs::Vector{String}
    assign_inputs::Union{Vector{String}, Nothing}
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    output::String
end

function get_metadata(cc::ClusterCard)
    return StringDict(
        "type" => cc.type,
        "method" => cc.method,
        "method_options" => get_options(cc.clusterer),
        "inputs" => cc.inputs,
        "assign_inputs" => cc.assign_inputs,
        "weights" => cc.weights,
        "partition" => cc.partition,
        "output" => cc.output,
    )
end

function ClusterCard(c::AbstractDict)
    type::String = c["type"]
    method::String = c["method"]
    method_options::StringDict = extract_options(c, "method", method)
    clusterer::ClusteringMethod = construct(CLUSTERING_METHODS[method], method_options)
    inputs::Vector{String} = c["inputs"]
    assign_inputs::Union{Vector{String}, Nothing} = get(c, "assign_inputs", nothing)
    if !isnothing(assign_inputs)
        issubset(assign_inputs, inputs) ||
            throw(ArgumentError("`assign_inputs` must be a subset of `inputs`"))
        clusterer isa KMeansMethod ||
            @warn "`assign_inputs` is only used by the `kmeans` method; ignored for `$method`"
    end
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    output::String = get(c, "output", "cluster")
    return ClusterCard(
        type,
        method,
        clusterer,
        inputs,
        assign_inputs,
        weights,
        partition,
        output,
    )
end

## StandardCard interface

SourceVariables(cc::ClusterCard) = SourceVariables(; cc.inputs, cc.weights, cc.partition)

OutputVariables(cc::ClusterCard) = OutputVariables([cc.output])

# The trained "model" retained (serialized) for evaluation, per method.
# k-means keeps its centroids so it can assign new rows; dbscan has no predict
# (Clustering.jl #63) so it keeps the training-row labels to re-emit them.
_model(::KMeansMethod, res, t, id_var) = (; centers = res.centers)          # features×K
_model(::DBSCANMethod, res, t, id_var) = (; label = assignments(res), id = t[id_var])

function _train(cc::ClusterCard, t, id_var::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), cc.inputs, dims = 1)
    weights = isnothing(cc.weights) ? nothing : t[cc.weights]
    res = cc.clusterer(X; weights)
    return _model(cc.clusterer, res, t, id_var)
end

# Assign each column of `X` (d×N) to the nearest of the K centroid columns of
# `C` (d×K) by squared Euclidean distance. Hand-rolled to avoid a Distances dep.
function _nearest(X::AbstractMatrix, C::AbstractMatrix)
    N, K = size(X, 2), size(C, 2)
    labels = Vector{Int}(undef, N)
    @inbounds for j in 1:N
        best, bestk = Inf, 1
        for k in 1:K
            s = 0.0
            for i in axes(X, 1)
                δ = X[i, j] - C[i, k]
                s += δ * δ
            end
            s < best && ((best, bestk) = (s, k))
        end
        labels[j] = bestk
    end
    return labels
end

# dbscan: no predict — re-emit the stored training-row labels by id.
_assign(::DBSCANMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey) =
    SimpleTable(id_var => model.id, cc.output => model.label)

# k-means: assign each row to the nearest fitted centroid, over `assign_inputs`.
function _assign(::KMeansMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey)
    ai = something(cc.assign_inputs, cc.inputs)
    idx = Vector{Int}(indexin(ai, cc.inputs))        # centroid rows for the assign dims
    X = stack(Fix1(getindex, t), ai, dims = 1)       # d×N in `ai` order
    labels = _nearest(X, model.centers[idx, :])
    return SimpleTable(id_var => t[id_var], cc.output => labels)
end

(cc::ClusterCard)(model, t, id_var::AbstractPrimaryKey) =
    _assign(cc.clusterer, cc, model, t, id_var)

## UI representation

function CardWidget(
        ::Type{ClusterCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(CLUSTERING_METHODS))
    support_weights = ["kmeans"]

    fields = vcat(
        [
            Widget("inputs", c),
            Widget("method", c, options = methods),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("weights", c, visible = "method" => support_weights, required = false),
            Widget("assign_inputs", c, visible = "method" => support_weights, required = false),
            Widget("partition", c, required = false),
            Widget("output", c),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
