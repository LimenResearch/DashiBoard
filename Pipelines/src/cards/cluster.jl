abstract type ClusteringMethod end

struct KMeansMethod <: ClusteringMethod
    classes::Int
    iterations::Int
    tol::Float64
    seed::Union{Int, Nothing}
end

function KMeansMethod(c::AbstractDict)
    classes::Int = c["classes"]
    iterations::Int = get(c, "iterations", 100)
    tol::Float64 = get(c, "tol", 1.0e-6)
    seed::Union{Int, Nothing} = get(c, "seed", nothing)
    return KMeansMethod(classes, iterations, tol, seed)
end

function (m::KMeansMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    return kmeans(X, classes; maxiter = iterations, tol, rng = get_rng(seed), weights)
end

struct DBSCANMethod <: ClusteringMethod
    radius::Float64
    min_neighbors::Int
    min_cluster_size::Int
end

function DBSCANMethod(c::AbstractDict)
    radius::Float64 = c["radius"]
    min_neighbors::Int = get(c, "min_neighbors", 1)
    min_cluster_size::Int = get(c, "min_cluster_size", 1)
    return DBSCANMethod(radius, min_neighbors, min_cluster_size)
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
        label::String
        method::String
        clusterer::ClusteringMethod
        inputs::Vector{String}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        output::String
    end

Cluster `inputs` based on `clusterer`.
Save resulting column as `output`.
"""
struct ClusterCard <: StandardCard
    type::String
    label::String
    method::String
    clusterer::ClusteringMethod
    inputs::Vector{String}
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    output::String
end

const CLUSTER_CARD_CONFIG = CardConfig{ClusterCard}(parse_toml_config("config", "cluster"))

function get_metadata(cc::ClusterCard)
    return StringDict(
        "type" => cc.type,
        "label" => cc.label,
        "method" => cc.method,
        "method_options" => get_options(cc.clusterer),
        "inputs" => cc.inputs,
        "weights" => cc.weights,
        "partition" => cc.partition,
        "output" => cc.output,
    )
end

function ClusterCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    method::String = c["method"]
    method_options::StringDict = extract_options(c, "method_options", METHOD_OPTIONS_REGEX)
    clusterer::ClusteringMethod = CLUSTERING_METHODS[method](method_options)
    inputs::Vector{String} = c["inputs"]
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    output::String = get(c, "output", "cluster")
    return ClusterCard(
        type,
        label,
        method,
        clusterer,
        inputs,
        weights,
        partition,
        output,
    )
end

## StandardCard interface

sorting_vars(::ClusterCard) = String[]
grouping_vars(::ClusterCard) = String[]
input_vars(cc::ClusterCard) = cc.inputs
target_vars(::ClusterCard) = String[]
weight_var(cc::ClusterCard) = cc.weights
partition_var(cc::ClusterCard) = cc.partition
output_vars(cc::ClusterCard) = [cc.output]

function _train(cc::ClusterCard, t, id; weights = nothing)
    X = stack(Fix1(getindex, t), cc.inputs, dims = 1)
    res = cc.clusterer(X; weights)
    label = assignments(res)
    return (; label, id) # return `label`s and relative `id`s for the evaluation
end

function (cc::ClusterCard)(model, t, _)
    # as `predict` is not implemented, we cannot fill in data points outside partition
    # https://github.com/JuliaStats/Clustering.jl/issues/63
    # we simply return those used for the prediction with the correct indices
    return SimpleTable(cc.output => model.label), model.id
end

## UI representation

function CardWidget(config::CardConfig{ClusterCard}, ::AbstractDict)
    methods = collect(keys(CLUSTERING_METHODS))

    fields = Widget[
        Widget("method", options = methods),
        Widget("inputs"),
        Widget("weights", visible = Dict("method" => ["kmeans"]), required = false),
        Widget("partition", required = false),
        Widget("output"),
    ]

    for (idx, m) in enumerate(methods)
        wdgs = config.methods[m]["widgets"]
        append!(fields, generate_widget.(wdgs, "method", m, idx))
    end

    return CardWidget(config.key, config.label, fields, OutputSpec("output"))
end
