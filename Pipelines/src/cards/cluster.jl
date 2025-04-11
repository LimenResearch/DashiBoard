const CLUSTERING_OPTIONS_REGEX = r"^clustering_options\.(.*)$"

struct Clusterer
    method::Base.Callable
    distance_mat::Bool
end

const CLUSTERERS = OrderedDict{String, Clusterer}(
    "kmeans" => Clusterer(kmeans, false),
    "kmedoids" => Clusterer(kmedoids, true),
    "dbscan" => Clusterer(dbscan, true),
)

struct ClusterCard <: AbstractCard
    clusterer::Clusterer
    model_options::Dict{Symbol, Any}
    training_options::Dict{Symbol, Any}
    columns::Vector{String}
    partition::Union{String, Nothing}
    output::String
end

function ClusterCard(c::AbstractDict)
    method::String = c[:method]
    clusterer::Clusterer = CLUSTERER[method]
    model_options::Dict{Symbol, Any} = extract_options(c, :model_options, MODEL_OPTIONS_REGEX)
    training_options::Dict{Symbol, Any} = extract_options(c, :training_options, MODEL_OPTIONS_REGEX)
    columns::Vector{String} = c[:columns]
    partition::Union{String, Nothing} = get(c, :partition, nothing)
    output::String = get(c, :output, "cluster")
    return ClusterCard(
        clusterer,
        model_options,
        training_options,
        columns,
        partition,
        output
    )
end

invertible(::ClusterCard) = false

inputs(cc::Cluster) = stringset(cc.columns, cc.partition)

outputs(cc::Cluster) = stringset(cc.output)

