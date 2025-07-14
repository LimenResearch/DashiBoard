function _kmeans(X; classes, iterations = 100, tol = 1.0e-6, seed = nothing, weights, options...)
    return kmeans(X, classes; maxiter = iterations, tol, rng = get_rng(seed), weights, options...)
end

function _dbscan(X; radius, weights, options...)
    isnothing(weights) || @warn "Weights not supported in DBSCAN"
    return dbscan(X, radius; options...)
end

const CLUSTERING_FUNCTIONS = OrderedDict{String, Function}(
    "kmeans" => _kmeans,
    "dbscan" => _dbscan,
)

struct Clusterer
    method::Function
    options::Dict{Symbol, Any}
end

function Clusterer(method_name::AbstractString, d::AbstractDict)
    method = CLUSTERING_FUNCTIONS[method_name]
    options = make(SymbolDict, d)
    # TODO: add preprocess for, e.g., metrics
    return Clusterer(method, options)
end

# TODO: support custom metrics
"""
    struct ClusterCard <: Card
        clusterer::Clusterer
        columns::Vector{String}
        partition::Union{String, Nothing}
        output::String
    end

Cluster `columns` based on `clusterer`.
Save resulting column as `output`.
"""
struct ClusterCard <: StandardCard
    clusterer::Clusterer
    weights::Union{String, Nothing}
    columns::Vector{String}
    partition::Union{String, Nothing}
    output::String
end

register_card("cluster", ClusterCard)

function ClusterCard(c::AbstractDict)
    method_name::String = c["method"]
    method_options::StringDict = extract_options(c, "method_options", METHOD_OPTIONS_REGEX)
    clusterer::Clusterer = Clusterer(method_name, method_options)
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    columns::Vector{String} = c["columns"]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    output::String = get(c, "output", "cluster")
    return ClusterCard(
        clusterer,
        weights,
        columns,
        partition,
        output
    )
end

## StandardCard interface

weights(cc::ClusterCard) = cc.weights
sorters(::ClusterCard) = String[]
partition(cc::ClusterCard) = cc.partition

predictors(cc::ClusterCard) = cc.columns
targets(::ClusterCard) = String[]
outputs(cc::ClusterCard) = [cc.output]

function _train(cc::ClusterCard, t, id; weights = nothing)
    X = stack(Fix1(getindex, t), cc.columns, dims = 1)
    res = cc.clusterer.method(X; weights, cc.clusterer.options...)
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

function CardWidget(::Type{ClusterCard})

    method_names = collect(keys(CLUSTERING_FUNCTIONS))

    fields = Widget[
        Widget("method", options = method_names),
        Widget("columns"),
        Widget("weights", visible = Dict("method" => ["kmeans"]), required = false),
        Widget("partition", required = false),
        Widget("output"),
    ]

    for (idx, m) in enumerate(method_names)
        method_config = parse_toml_config("cluster", m)
        wdgs = get(method_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, "method", m, idx))
    end

    return CardWidget(;
        type = "cluster",
        label = "Cluster",
        output = OutputSpec("output"),
        fields
    )
end
