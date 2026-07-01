abstract type ClusteringMethod end

@kwarg struct KMeansMethod <: ClusteringMethod
    classes::Int & (dashi = StringDict("minimum" => 1),)
    iterations::Int = 100 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
    seed::Union{Int, Nothing} = nothing & (dashi = StringDict("minimum" => 0),)
end

KMeansMethod(c::AbstractDict) = StructUtils.make(KMeansMethod, c, DashiStyle())

function (m::KMeansMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    return kmeans(X, classes; maxiter = iterations, tol, rng = get_rng(seed), weights)
end

@kwarg struct DBSCANMethod <: ClusteringMethod
    radius::Float64 & (dashi = StringDict("exclusiveMinimum" => 0),)
    min_neighbors::Int = 1 & (dashi = StringDict("minimum" => 1),)
    min_cluster_size::Int = 1 & (dashi = StringDict("minimum" => 1),)
end

DBSCANMethod(c::AbstractDict) = StructUtils.make(DBSCANMethod, c, DashiStyle())

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
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        output::String
    end

Cluster `inputs` based on `clusterer`.
Save resulting column as `output`.
"""
struct ClusterCard <: StandardCard
    type::String
    method::String
    clusterer::ClusteringMethod
    inputs::Vector{String}
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
        "weights" => cc.weights,
        "partition" => cc.partition,
        "output" => cc.output,
    )
end

function ClusterCard(c::AbstractDict)
    type::String = c["type"]
    method::String = c["method"]
    method_options::StringDict = extract_options(c, "method", method)
    clusterer::ClusteringMethod = CLUSTERING_METHODS[method](method_options)
    inputs::Vector{String} = c["inputs"]
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    output::String = get(c, "output", "cluster")
    return ClusterCard(
        type,
        method,
        clusterer,
        inputs,
        weights,
        partition,
        output,
    )
end

## StandardCard interface

SourceVariables(cc::ClusterCard) = SourceVariables(; cc.inputs, cc.weights, cc.partition)

OutputVariables(cc::ClusterCard) = OutputVariables([cc.output])

function _train(cc::ClusterCard, t, id_var::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), cc.inputs, dims = 1)
    weights = isnothing(cc.weights) ? nothing : t[cc.weights]
    res = cc.clusterer(X; weights)
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
