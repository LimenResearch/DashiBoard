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
    res = dbscan(X, radius; min_neighbors, min_cluster_size)
    # core points and their clusters, the state DBSCAN's own border rule
    # needs to label rows at evaluation time
    cores = [i for c in res.clusters for i in c.core_indices]
    return (;
        label = assignments(res),
        core_points = X[:, cores],
        core_label = [k for (k, c) in enumerate(res.clusters) for _ in c.core_indices],
        radius,
    )
end

"""
    AffinityPropagationMethod <: ClusteringMethod

Affinity propagation (`"method" => "affinity_propagation"`): points exchange
messages until a set of exemplars — actual fitted points — emerges, so the
number of clusters comes from the data instead of being predeclared.
`preference` (each point's self-similarity; more negative → fewer clusters)
defaults to the median of the pairwise similarities; `damp`, `maxiter` and
`tol` control the message passing. The similarity matrix is the negative
squared Euclidean distance over the card's `inputs`, built densely: the fit
is O(N²) in the training rows. Evaluation assigns each row to the nearest
exemplar — affinity propagation's own assignment rule, so training rows
reproduce their fit labels.
"""
@kwarg struct AffinityPropagationMethod <: ClusteringMethod
    damp::Float64 = 0.5 & (dashi = StringDict("minimum" => 0, "exclusiveMaximum" => 1),)
    maxiter::Int = 200 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
    preference::Union{Float64, Nothing} = nothing
end

function (m::AffinityPropagationMethod)(X; weights)
    (; damp, maxiter, tol, preference) = m
    isnothing(weights) || @warn "Weights not supported in affinity propagation"
    S = -pairwise(SqEuclidean(), X, dims = 2)
    # median of the similarities (the zero diagonal included, matching the
    # convention popularized by sklearn) gives a moderate number of clusters
    pref = something(preference, median(vec(S)))
    for i in axes(S, 1)
        S[i, i] = pref
    end
    res = affinityprop(S; maxiter, tol, damp)
    res.converged ||
        @warn "Affinity propagation did not converge; increase `maxiter` or adjust `damp`"
    return (; centers = X[:, res.exemplars], res.converged)
end

"""
    CLUSTER_METRICS

Open lookup table of dissimilarity metrics for the matrix-based clustering
methods (currently `kmedoids`): maps a name to a constructor
`options::AbstractDict -> metric`, where the metric is any callable
`(u, v) -> Real` (Distances.jl metrics are callable and get the fast
`pairwise` path). Register custom metrics the same way methods are
registered — configuration lives behind the name, as it does for
streamliner's model configs and the window-function closures. A suggested
convention for parameterized metrics, until options can travel in the card,
is a name stating the configuration:

    CLUSTER_METRICS["space_time_k60"] = _ -> SpaceTimeMetric(60.0)

The card selects it with `"metric": "space_time_k60"`. Constructors are
currently always called with the default (empty) options — TODO: once the
schema system can express object-valued fields (schema rework in progress;
window_function.jl carries the same limitation as a TODO), add
`metric_options` to the metric-based method structs and pass it here, so
parameters move from the registered name into the card.
"""
const CLUSTER_METRICS = OrderedDict{String, Any}(
    "euclidean" => _ -> Euclidean(),
    "sqeuclidean" => _ -> SqEuclidean(),
    "cityblock" => _ -> Cityblock(),
    "chebyshev" => _ -> Chebyshev(),
)

# componentwise metrics, the only ones `assign_inputs` can restrict
# meaningfully — a custom metric defines its own use of the inputs
const RESTRICTABLE_METRICS = Set(["euclidean", "sqeuclidean", "cityblock", "chebyshev"])

_dissimilarities(metric::PreMetric, X::AbstractMatrix, C::AbstractMatrix) =
    pairwise(metric, C, X, dims = 2)                                        # K×N
_dissimilarities(metric, X::AbstractMatrix, C::AbstractMatrix) =
    [metric(view(C, :, k), view(X, :, j)) for k in axes(C, 2), j in axes(X, 2)]

"""
    KMedoidsMethod <: ClusteringMethod

k-medoids (`"method" => "kmedoids"`, Clustering.jl `kmedoids`): like k-means
with `classes` predeclared, but the cluster centers are medoids — actual
fitted points minimizing the total dissimilarity to their cluster's members —
and the dissimilarity is pluggable: `metric` names an entry of
[`CLUSTER_METRICS`](@ref), so custom coupling functions (e.g. space–time)
can drive the clustering. The pairwise
dissimilarity matrix is built densely: the fit is O(N²) in the training
rows. With a `seed` the k-means++ seeding is drawn from a seeded generator,
making the fit reproducible. Evaluation assigns each row to the nearest
medoid under the SAME metric — the method's own rule; ties go to the
earliest-fitted medoid.
"""
@kwarg struct KMedoidsMethod <: ClusteringMethod
    classes::Int & (dashi = StringDict("minimum" => 1),)
    iterations::Int = 200 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-8 & (dashi = StringDict("exclusiveMinimum" => 0),)
    seed::Union{Int, Nothing} = nothing & (dashi = StringDict("minimum" => 0),)
    metric::String = "euclidean"
end

function (m::KMedoidsMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    isnothing(weights) || @warn "Weights not supported in k-medoids"
    # TODO: pass the card's `metric_options` once the schema system can
    # express object-valued fields (see CLUSTER_METRICS)
    metric = CLUSTER_METRICS[m.metric](StringDict())
    D = _dissimilarities(metric, X, X)
    init = isnothing(seed) ? :kmpp :
        initseeds_by_costs(:kmpp, D, classes; rng = get_rng(seed))
    res = kmedoids(D, classes; maxiter = iterations, tol, init)
    res.converged || @warn "k-medoids did not converge; increase `iterations`"
    return (; centers = X[:, res.medoids], res.converged)
end

const CLUSTERING_METHODS = OrderedDict{String, DataType}(
    "kmeans" => KMeansMethod,
    "dbscan" => DBSCANMethod,
    "affinity_propagation" => AffinityPropagationMethod,
    "kmedoids" => KMedoidsMethod,
)

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

Evaluation labels rows with the fitted state, so a trained card can label rows
outside the training set: `kmeans` and `affinity_propagation` assign each row
to the nearest fitted center (centroid / exemplar); `dbscan` assigns each row
to the cluster of the nearest fitted core point within `radius` — its own
border rule — and to noise (0) beyond it, so rows far from every fitted
cluster stay visible as noise instead of being absorbed. Assignment is
single-label: a row equidistant from several centers or core points is
deterministically resolved to the earliest-fitted one. `assign_inputs` (a
subset of `inputs`, defaulting to all of them) selects which dimensions the
assignment distance uses — e.g. cluster on space and time but assign on space
only.
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
    isnothing(assign_inputs) || issubset(assign_inputs, inputs) ||
        throw(ArgumentError("`assign_inputs` must be a subset of `inputs`"))
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
# k-means, affinity propagation and k-medoids keep their centers (centroids /
# exemplar points / medoid points); dbscan keeps its core points (plus the
# fit labels and ids as the record of the fit).
_model(::KMeansMethod, res, t, id_var) = (; centers = res.centers)          # features×K
_model(::AffinityPropagationMethod, res, t, id_var) = (; res.centers, res.converged)  # features×K
_model(::KMedoidsMethod, res, t, id_var) = (; res.centers, res.converged)   # features×K
_model(::DBSCANMethod, res, t, id_var) = (;
    res.label,
    id = t[id_var],
    res.core_points,                                                        # features×n_core
    res.core_label,
    res.radius,
)

function _train(cc::ClusterCard, t, id_var::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), cc.inputs, dims = 1)
    weights = isnothing(cc.weights) ? nothing : t[cc.weights]
    res = cc.clusterer(X; weights)
    return _model(cc.clusterer, res, t, id_var)
end

"""
    _nearest(X, C)

Assign each column of `X` (d×N) to the nearest of the K centroid columns of
`C` (d×K) by squared Euclidean distance, ties to the smallest column index
(`argmin` returns the first minimum). Uses `Distances.pairwise` — the
predict recommended in Clustering.jl#63, BLAS-backed, and Distances is
already in the dependency tree via Clustering itself.
"""
function _nearest(X::AbstractMatrix, C::AbstractMatrix)
    D = pairwise(SqEuclidean(), C, X, dims = 2)   # K×N
    return [argmin(view(D, :, j)) for j in axes(D, 2)]
end

"""
    _nearest_within(X, C, labels, radius)

The cluster of the nearest of the `C` columns within `radius` of each `X`
column (`labels[k]` is column k's cluster), 0 beyond the radius — DBSCAN's
own border rule, applied out of sample. A KD-tree shortlists the columns
within `radius` (the same structure the dbscan fit itself builds), so the
scan is over neighbors instead of every core point.

Assignment is single-label, so exact distance ties must collapse to one
winner: the smallest column index (i.e. the earliest-fitted core point)
wins. The rule matters because the KD-tree returns its shortlist in
traversal order, which would otherwise decide ties as an implementation
accident — and ties are common under discrete-valued or single-dimension
`assign_inputs`. It also keeps results identical to a full left-to-right
scan. Rows with non-finite coordinates stay 0.
"""
function _nearest_within(X::AbstractMatrix, C::AbstractMatrix, labels::Vector{Int}, radius::Real)
    out = zeros(Int, size(X, 2))
    isempty(labels) && return out
    Cf = convert(Matrix{Float64}, C)
    finite = [j for j in axes(X, 2) if all(isfinite, view(X, :, j))]
    Xq = convert(Matrix{Float64}, X[:, finite])
    hits = inrange(KDTree(Cf), Xq, radius)
    @inbounds for (jf, j) in enumerate(finite)
        best, bestk = Inf, 0
        for k in hits[jf]
            s = 0.0
            for i in axes(Cf, 1)
                δ = Xq[i, jf] - Cf[i, k]
                s += δ * δ
            end
            if s < best || (s == best && k < bestk)
                best, bestk = s, k
            end
        end
        bestk == 0 || (out[j] = labels[bestk])
    end
    return out
end

# dbscan: assign each row to the cluster of the nearest fitted core point
# within `radius`, over `assign_inputs`; rows with no core point in reach are
# noise (0).
function _assign(::DBSCANMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey)
    ai = something(cc.assign_inputs, cc.inputs)
    idx = Vector{Int}(indexin(ai, cc.inputs))        # core rows for the assign dims
    X = stack(Fix1(getindex, t), ai, dims = 1)       # d×N in `ai` order
    labels = _nearest_within(X, model.core_points[idx, :], model.core_label, model.radius)
    return SimpleTable(id_var => t[id_var], cc.output => labels)
end

"""
    _assign_nearest(cc, model, t, id_var)

Label each row with the nearest of the fitted centers (`model.centers`,
features×K) over `assign_inputs` — the shared predict of the centers-shaped
methods (k-means centroids, affinity-propagation exemplars).
"""
function _assign_nearest(cc::ClusterCard, model, t, id_var::AbstractPrimaryKey)
    ai = something(cc.assign_inputs, cc.inputs)
    idx = Vector{Int}(indexin(ai, cc.inputs))        # center rows for the assign dims
    X = stack(Fix1(getindex, t), ai, dims = 1)       # d×N in `ai` order
    labels = _nearest(X, model.centers[idx, :])
    return SimpleTable(id_var => t[id_var], cc.output => labels)
end

_assign(::KMeansMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey) =
    _assign_nearest(cc, model, t, id_var)

_assign(::AffinityPropagationMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey) =
    _assign_nearest(cc, model, t, id_var)

# k-medoids: nearest medoid under the SAME metric the fit used (ties to the
# earliest-fitted medoid). Restricting dimensions is only meaningful for the
# componentwise built-in metrics; a custom metric defines its own use of the
# inputs, so `assign_inputs` is rejected there.
function _assign(m::KMedoidsMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey)
    isnothing(cc.assign_inputs) || m.metric in RESTRICTABLE_METRICS ||
        throw(ArgumentError("`assign_inputs` requires a componentwise metric ($(join(sort!(collect(RESTRICTABLE_METRICS)), ", "))); \"$(m.metric)\" defines its own use of the inputs"))
    ai = something(cc.assign_inputs, cc.inputs)
    idx = Vector{Int}(indexin(ai, cc.inputs))        # medoid rows for the assign dims
    X = stack(Fix1(getindex, t), ai, dims = 1)       # d×N in `ai` order
    metric = CLUSTER_METRICS[m.metric](StringDict())
    D = _dissimilarities(metric, X, model.centers[idx, :])
    labels = [argmin(view(D, :, j)) for j in axes(D, 2)]
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
            Widget("assign_inputs", c, visible = "method" => methods, required = false),
            Widget("partition", c, required = false),
            Widget("output", c),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
