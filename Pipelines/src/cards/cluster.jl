abstract type ClusteringMethod end

"""
    KMeansMethod <: ClusteringMethod

k-means (`"method" => "kmeans"`). `init` picks the seeding algorithm and
`metric` the semimetric by [`CLUSTER_METRICS`](@ref) name (a Distances.jl
semimetric is required; plain-function registry entries are for `kmedoids`).
The default, squared Euclidean, is the canonical k-means objective — with
any other semimetric the center update remains the arithmetic mean, which is
only the true minimizer under squared Euclidean, so the fit becomes a
reasonable heuristic without the usual convergence guarantee. Evaluation
assigns each row to the nearest fitted centroid under the SAME metric.
"""
@kwarg struct KMeansMethod <: ClusteringMethod
    classes::Int & (dashi = StringDict("minimum" => 1),)
    iterations::Int = 100 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
    seed::Union{Int, Nothing} = nothing & (dashi = StringDict("minimum" => 0),)
    init::String = "kmpp" & (dashi = StringDict("enum" => ["kmpp", "rand", "kmcen"]),)
    metric::String = "sqeuclidean"
end

function (m::KMeansMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    metric = _cluster_metric(m.metric)
    metric isa SemiMetric || throw(ArgumentError(
        "kmeans requires a Distances.jl semimetric; \"$(m.metric)\" is a plain-function metric (usable by kmedoids)"
    ))
    return kmeans(
        X, classes;
        maxiter = iterations, tol, rng = get_rng(seed), weights,
        init = Symbol(m.init), distance = metric,
    )
end

"""
    DBSCANMethod <: ClusteringMethod

DBSCAN (`"method" => "dbscan"`). `metric` is a [`CLUSTER_METRICS`](@ref)
name restricted to true metrics — the KD-trees behind both the fit and the
nearest-core predict require the triangle inequality, so `sqeuclidean` and
plain-function entries are refused. Fit and predict use the SAME metric.
"""
# true metrics only: KD-trees (Clustering's dbscan fit and our
# _nearest_within predict) rely on the triangle inequality
const DBSCAN_METRICS = ["euclidean", "cityblock", "chebyshev"]

@kwarg struct DBSCANMethod <: ClusteringMethod
    radius::Float64 & (dashi = StringDict("exclusiveMinimum" => 0),)
    min_neighbors::Int = 1 & (dashi = StringDict("minimum" => 1),)
    min_cluster_size::Int = 1 & (dashi = StringDict("minimum" => 1),)
    metric::String = "euclidean" & (dashi = StringDict("enum" => DBSCAN_METRICS),)
end

function (m::DBSCANMethod)(X; weights)
    (; radius, min_neighbors, min_cluster_size) = m
    isnothing(weights) || @warn "Weights not supported in DBSCAN"
    m.metric in DBSCAN_METRICS ||
        throw(ArgumentError("dbscan requires a true metric ($(join(DBSCAN_METRICS, ", "))); got \"$(m.metric)\""))
    metric = _cluster_metric(m.metric)
    res = dbscan(X, radius; metric, min_neighbors, min_cluster_size)
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
defaults to the value `preference_rule` picks from the pairwise
similarities — their `"median"` (moderate number of clusters, the sklearn
convention) or their `"min"` (fewer); `damp`, `maxiter` and `tol` control
the message passing. The similarity matrix is the negative
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
    preference_rule::String = "median" & (dashi = StringDict("enum" => ["median", "min"]),)
end

function (m::AffinityPropagationMethod)(X; weights)
    (; damp, maxiter, tol, preference, preference_rule) = m
    isnothing(weights) || @warn "Weights not supported in affinity propagation"
    preference_rule in ("median", "min") ||
        throw(ArgumentError("`preference_rule` must be \"median\" or \"min\", got \"$preference_rule\""))
    S = -pairwise(SqEuclidean(), X, dims = 2)
    # when `preference` is not given, `preference_rule` picks the classic
    # default: the median of the similarities (zero diagonal included,
    # matching the convention popularized by sklearn) for a moderate number
    # of clusters, or their minimum for fewer
    pref = something(
        preference,
        preference_rule == "min" ? minimum(vec(S)) : median(vec(S)),
    )
    for i in axes(S, 1)
        S[i, i] = pref
    end
    res = affinityprop(S; maxiter, tol, damp)
    res.converged ||
        @warn "Affinity propagation did not converge; increase `maxiter` or adjust `damp`"
    return (; centers = X[:, res.exemplars], res.converged, preference = pref)
end

"""
    CLUSTER_METRICS

Open lookup table behind every method's metric option: maps a name to a
constructor `options::AbstractDict -> metric`. It is the single source —
each method then narrows what it accepts: `kmedoids` takes any callable
`(u, v) -> Real`, `kmeans` requires a Distances.jl semimetric, `dbscan` a
true metric (see `DBSCAN_METRICS`). Distances.jl metrics are callable and
get the fast `pairwise` path. Register custom metrics the same way methods
are registered — configuration lives behind the name, as it does for
streamliner's model configs and the window-function closures. A suggested
convention for parameterized metrics, until options can travel in the card,
is a name stating the configuration:

    CLUSTER_METRICS["space_time_k60"] = _ -> SpaceTimeMetric(60.0)

The card selects it with `"metric": "space_time_k60"`.
"""
const CLUSTER_METRICS = OrderedDict{String, Any}(
    "euclidean" => _ -> Euclidean(),
    "sqeuclidean" => _ -> SqEuclidean(),
    "cityblock" => _ -> Cityblock(),
    "chebyshev" => _ -> Chebyshev(),
)

# TODO: pass the card's `metric_options` once the schema system can express
# object-valued fields (schema rework in progress; window_function.jl
# carries the same limitation as a TODO) — until then constructors always
# receive the default (empty) options and parameters live in the registered
# name.
function _cluster_metric(name::AbstractString)
    haskey(CLUSTER_METRICS, name) || throw(ArgumentError(
        "unknown cluster metric \"$name\"; available: $(join(keys(CLUSTER_METRICS), ", ")) — register custom metrics in `Pipelines.CLUSTER_METRICS`"
    ))
    return CLUSTER_METRICS[name](StringDict())
end

# componentwise metrics, the only ones `assign_inputs` can restrict
# meaningfully — a custom metric defines its own use of the inputs
const RESTRICTABLE_METRICS = Set(["euclidean", "sqeuclidean", "cityblock", "chebyshev"])

function _check_restrictable(assign_inputs, name::AbstractString)
    isnothing(assign_inputs) || name in RESTRICTABLE_METRICS || throw(ArgumentError(
        "`assign_inputs` requires a componentwise metric ($(join(sort!(collect(RESTRICTABLE_METRICS)), ", "))); \"$name\" defines its own use of the inputs"
    ))
    return
end

"""
    _dissimilarities(metric, X, C)

The dense dissimilarity matrix between the columns of `C` (d×K) and the
columns of `X` (d×N), oriented K×N — one row per `C` column. Distances.jl
metrics take the BLAS-backed `pairwise` path; any other callable
`(u, v) -> Real` is applied pairwise.
"""
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
can drive the clustering. The pairwise dissimilarity matrix is built
densely: the fit is O(N²) in the training rows. With a `seed`, the chosen
`init` seeding is drawn from a seeded generator (`initseeds_by_costs`),
making the fit reproducible. Evaluation assigns each row to the nearest
medoid under the SAME metric — the method's own rule; ties go to the
earliest-fitted medoid.
"""
@kwarg struct KMedoidsMethod <: ClusteringMethod
    classes::Int & (dashi = StringDict("minimum" => 1),)
    iterations::Int = 200 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-8 & (dashi = StringDict("exclusiveMinimum" => 0),)
    seed::Union{Int, Nothing} = nothing & (dashi = StringDict("minimum" => 0),)
    init::String = "kmpp" & (dashi = StringDict("enum" => ["kmpp", "rand", "kmcen"]),)
    metric::String = "euclidean"
end

function (m::KMedoidsMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    isnothing(weights) || @warn "Weights not supported in k-medoids"
    metric = _cluster_metric(m.metric)
    D = _dissimilarities(metric, X, X)
    init = isnothing(seed) ? Symbol(m.init) :
        initseeds_by_costs(Symbol(m.init), D, classes; rng = get_rng(seed))
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
outside the training set: `kmeans`, `affinity_propagation` and `kmedoids`
assign each row to the nearest fitted center (centroid / exemplar / medoid),
`kmeans` and `kmedoids` under the SAME metric as their fit; `dbscan` assigns
each row to the cluster of the nearest fitted core point within `radius` —
its own border rule — and to noise (0) beyond it, so rows far from every
fitted cluster stay visible as noise instead of being absorbed. Assignment is
single-label: a row equidistant from several centers or core points is
deterministically resolved to the earliest-fitted one. `assign_inputs` (a
subset of `inputs`, defaulting to all of them) selects which dimensions the
assignment distance uses — e.g. cluster on space and time but assign on space
only; it is only allowed with componentwise metrics — a custom metric defines
its own use of the inputs and rejects it.
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
_model(::AffinityPropagationMethod, res, t, id_var) = (; res.centers, res.converged, res.preference)  # features×K
_model(::KMedoidsMethod, res, t, id_var) = (; res.centers, res.converged)   # features×K
_model(::DBSCANMethod, res, t, id_var) = (;
    res.label,           # fit labels: unread by evaluation, retained with the
    id = t[id_var],      # ids as the provenance record of the fit
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
    _nearest(X, C, metric = SqEuclidean())

Assign each column of `X` (d×N) to the nearest of the K center columns of
`C` (d×K) under `metric` — any [`CLUSTER_METRICS`](@ref) entry — with ties
to the smallest column index (`argmin` returns the first minimum).
Distances.jl metrics take the BLAS-backed `pairwise` path (the predict
recommended in Clustering.jl#63; Distances is already in the dependency
tree via Clustering itself).
"""
function _nearest(X::AbstractMatrix, C::AbstractMatrix, metric = SqEuclidean())
    D = _dissimilarities(metric, X, C)   # K×N
    return [argmin(view(D, :, j)) for j in axes(D, 2)]
end

"""
    _nearest_within(X, C, labels, radius, metric = Euclidean())

The cluster of the nearest of the `C` columns within `radius` of each `X`
column (`labels[k]` is column k's cluster), 0 beyond the radius — DBSCAN's
own border rule, applied out of sample under the same `metric` as the fit.
A KD-tree shortlists the columns within `radius` (the same structure the
dbscan fit itself builds), so the scan is over neighbors instead of every
core point.

Assignment is single-label, so exact distance ties must collapse to one
winner: the smallest column index (i.e. the earliest-fitted core point)
wins. The rule matters because the KD-tree returns its shortlist in
traversal order, which would otherwise decide ties as an implementation
accident — and ties are common under discrete-valued or single-dimension
`assign_inputs`. It also keeps results identical to a full left-to-right
scan. Rows with non-finite coordinates stay 0.
"""
function _nearest_within(
        X::AbstractMatrix, C::AbstractMatrix, labels::Vector{Int}, radius::Real,
        metric::Metric = Euclidean(),
    )
    out = zeros(Int, size(X, 2))
    isempty(labels) && return out
    Cf = convert(Matrix{Float64}, C)
    finite = [j for j in axes(X, 2) if all(isfinite, view(X, :, j))]
    Xq = convert(Matrix{Float64}, X[:, finite])
    hits = inrange(KDTree(Cf, metric), Xq, radius)
    @inbounds for (jf, j) in enumerate(finite)
        best, bestk = Inf, 0
        for k in hits[jf]
            s = metric(view(Xq, :, jf), view(Cf, :, k))
            if s < best || (s == best && k < bestk)
                best, bestk = s, k
            end
        end
        bestk == 0 || (out[j] = labels[bestk])
    end
    return out
end

"""
    _assign(cc::ClusterCard, model, t, id_var, metric)

Label each row with the nearest of the fitted centers (`model.centers`,
features×K) under `metric` over `assign_inputs` — the shared predict of the
centers-shaped methods: k-means centroids, affinity-propagation exemplars,
k-medoids medoids. Ties go to the earliest-fitted center (see `_nearest`).
"""
function _assign(cc::ClusterCard, model, t, id_var::AbstractPrimaryKey, metric)
    ai = something(cc.assign_inputs, cc.inputs)
    idx = Vector{Int}(indexin(ai, cc.inputs))        # center rows for the assign dims
    X = stack(Fix1(getindex, t), ai, dims = 1)       # d×N in `ai` order
    labels = _nearest(X, model.centers[idx, :], metric)
    return SimpleTable(id_var => t[id_var], cc.output => labels)
end

# k-means and k-medoids: nearest center under the SAME metric the fit used.
function _assign(m::Union{KMeansMethod, KMedoidsMethod}, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey)
    _check_restrictable(cc.assign_inputs, m.metric)
    return _assign(cc, model, t, id_var, _cluster_metric(m.metric))
end

_assign(::AffinityPropagationMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey) =
    _assign(cc, model, t, id_var, SqEuclidean())

# dbscan: assign each row to the cluster of the nearest fitted core point
# within `radius`, over `assign_inputs`, under the card's metric; rows with
# no core point in reach are noise (0).
function _assign(m::DBSCANMethod, cc::ClusterCard, model, t, id_var::AbstractPrimaryKey)
    ai = something(cc.assign_inputs, cc.inputs)
    idx = Vector{Int}(indexin(ai, cc.inputs))        # core rows for the assign dims
    X = stack(Fix1(getindex, t), ai, dims = 1)       # d×N in `ai` order
    metric = _cluster_metric(m.metric)
    labels = _nearest_within(X, model.core_points[idx, :], model.core_label, model.radius, metric)
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
            # every method honors assign_inputs; the visible kwarg only
            # hides the field until a method is picked
            Widget("assign_inputs", c, visible = "method" => methods, required = false),
            Widget("partition", c, required = false),
            Widget("output", c),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
