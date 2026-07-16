"""
    DissimilarityMethod <: AbstractMethod

Configuration of a dissimilarity between feature vectors, selected in JSON
by `"type"` (e.g. `{"type": "minkowski", "p": 3}`) like any other method.
Each concrete type implements [`get_dissimilarity`](@ref), and cards carry
one as a typed field (see `KMeansMethod`), so its options are part of the
card schema and travel with the card.

The subtype [`MetricMethod`](@ref) marks true metrics: a clustering method
that requires the triangle inequality constrains its field to it, and both
parsing and the generated schema then only accept that subset.
"""
abstract type DissimilarityMethod <: AbstractMethod end

"""
    MetricMethod <: DissimilarityMethod

A [`DissimilarityMethod`](@ref) that is a true metric (satisfies the
triangle inequality) — the requirement of KD-tree-backed methods such as
`dbscan`. Registered in `METRIC_METHODS`, a subset of
`DISSIMILARITY_METHODS`.
"""
abstract type MetricMethod <: DissimilarityMethod end

# semimetrics (no triangle inequality)

@kwarg struct SqEuclideanMethod <: DissimilarityMethod end

@kwarg struct WeightedSqEuclideanMethod <: DissimilarityMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

# true metrics

@kwarg struct EuclideanMethod <: MetricMethod end

@kwarg struct CityblockMethod <: MetricMethod end

@kwarg struct ChebyshevMethod <: MetricMethod end

# a true metric only for p ≥ 1 (fractional p breaks the triangle inequality)
@kwarg struct MinkowskiMethod <: MetricMethod
    p::Float64 = 2.0 & (dashi = json_number(minimum = 1),)
end

@kwarg struct WeightedEuclideanMethod <: MetricMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

@kwarg struct WeightedCityblockMethod <: MetricMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

@kwarg struct WeightedMinkowskiMethod <: MetricMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
    p::Float64 = 2.0 & (dashi = json_number(minimum = 1),)
end

"""
    get_dissimilarity(m::DissimilarityMethod)

The Distances.jl object a `DissimilarityMethod` configures — usable
everywhere the Distances API is (`pairwise`, the `distance` keyword of
`kmeans`, the `metric` keyword of `dbscan`, ...), keeping its optimized
evaluation paths.
"""
get_dissimilarity(::SqEuclideanMethod) = SqEuclidean()
get_dissimilarity(m::WeightedSqEuclideanMethod) = WeightedSqEuclidean(m.weights)
get_dissimilarity(::EuclideanMethod) = Euclidean()
get_dissimilarity(::CityblockMethod) = Cityblock()
get_dissimilarity(::ChebyshevMethod) = Chebyshev()
get_dissimilarity(m::MinkowskiMethod) = Minkowski(m.p)
get_dissimilarity(m::WeightedEuclideanMethod) = WeightedEuclidean(m.weights)
get_dissimilarity(m::WeightedCityblockMethod) = WeightedCityblock(m.weights)
get_dissimilarity(m::WeightedMinkowskiMethod) = WeightedMinkowski(m.weights, m.p)

const METRIC_METHODS = OrderedDict{String, Type}(
    "euclidean" => EuclideanMethod,
    "cityblock" => CityblockMethod,
    "chebyshev" => ChebyshevMethod,
    "minkowski" => MinkowskiMethod,
    "weighted_euclidean" => WeightedEuclideanMethod,
    "weighted_cityblock" => WeightedCityblockMethod,
    "weighted_minkowski" => WeightedMinkowskiMethod,
)

const DISSIMILARITY_METHODS = merge(
    OrderedDict{String, Type}(
        "sqeuclidean" => SqEuclideanMethod,
        "weighted_sqeuclidean" => WeightedSqEuclideanMethod,
    ),
    METRIC_METHODS,
)

# The macro gives automatically
# construct(DissimilarityMethod, d::AbstractDict)
# schema + lowering (for metadata)

@options DissimilarityMethod DISSIMILARITY_METHODS
@options MetricMethod METRIC_METHODS
