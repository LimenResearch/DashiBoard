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

"""
    AffinityPropagationMethod <: ClusteringMethod

Affinity propagation (`"method" => "affinity_propagation"`): points exchange
messages until a set of exemplars — actual fitted points — emerges, so the
number of clusters comes from the data instead of being predeclared.
`damp`, `maxiter` and `tol` control the message passing. The similarity
matrix is the negative squared Euclidean distance over the card's `inputs`,
built densely: the fit is O(N²) in the training rows. Each point's
self-similarity (its preference; more negative → fewer clusters) is set to
the median of its similarities, the classic default for a moderate number
of clusters.
"""
@kwarg struct AffinityPropagationMethod <: ClusteringMethod
    damp::Float64 = 0.5 & (dashi = StringDict("minimum" => 0, "exclusiveMaximum" => 1),)
    maxiter::Int = 200 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
end

function (m::AffinityPropagationMethod)(X; weights)
    (; damp, maxiter, tol) = m
    isnothing(weights) || @warn "Weights not supported in affinity propagation"
    S = -pairwise(SqEuclidean(), X, dims = 2)
    S[diagind(S)] .= vec(median(S, dims = 1))
    res = affinityprop(S; maxiter, tol, damp)
    res.converged ||
        @warn "Affinity propagation did not converge; increase `maxiter` or adjust `damp`"
    return res
end

const CLUSTERING_METHODS = OrderedDict{String, DataType}(
    "kmeans" => KMeansMethod,
    "dbscan" => DBSCANMethod,
    "affinity_propagation" => AffinityPropagationMethod,
)

choose_clusterer(d::AbstractDict) = get_method(d, CLUSTERING_METHODS)

@choosetype DashiStyle ClusteringMethod choose_clusterer

# TODO: support custom metrics
"""
    struct ClusterCard{M <: ClusteringMethod} <: StandardCard
        method::M
        inputs::Vector{String}
        weights::Union{String, Nothing} = nothing
        partition::Union{String, Nothing} = nothing
        output::String
    end

Cluster `inputs` based on `method`.
Save resulting column as `output`.
"""
@kwarg struct ClusterCard{M <: ClusteringMethod} <: StandardCard
    method::M
    inputs::Vector{String}
    weights::Union{String, Nothing} = nothing
    partition::Union{String, Nothing} = nothing
    output::String
end

get_metadata(cc::ClusterCard) = _get_metadata(cc, CLUSTERING_METHODS)

ClusterCard(c::AbstractDict) = construct(ClusterCard, c)

## StandardCard interface

SourceVariables(cc::ClusterCard) = SourceVariables(; cc.inputs, cc.weights, cc.partition)

OutputVariables(cc::ClusterCard) = OutputVariables([cc.output])

function _train(cc::ClusterCard, t, id_var::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), cc.inputs, dims = 1)
    weights = isnothing(cc.weights) ? nothing : t[cc.weights]
    res = cc.method(X; weights)
    label = assignments(res)
    return (; label, id = t[id_var]) # return `label`s and relative `id`s for the evaluation
end

function (cc::ClusterCard)(model, t, id_var::AbstractPrimaryKey)
    # as `predict` is not implemented, we cannot fill in data points outside partition
    # https://github.com/JuliaStats/Clustering.jl/issues/63
    # we simply return those used for the prediction with the correct indices
    return SimpleTable(id_var => model.id, cc.output => model.label)
end

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
            Widget("partition", c, required = false),
            Widget("output", c),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
