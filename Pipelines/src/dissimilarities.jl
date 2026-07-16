"""
    DissimilarityMethod <: AbstractMethod

Configuration of a dissimilarity between feature vectors, selected in JSON
by `"type"` (e.g. `{"type": "minkowski", "p": 3}`) like any other method.
Each concrete type implements [`get_dissimilarity`](@ref), and cards carry
one as a typed field (see `KMeansMethod`), so its options are part of the
card schema and travel with the card.
A dissimilarity promises only a non-negative "how different" score, zero
from a point to itself — weaker than a true distance.

The subtype [`MetricMethod`](@ref) marks true metrics: a clustering method
that requires the triangle inequality constrains its field to it, and both
parsing and the generated schema then only accept that subset.
"""
abstract type DissimilarityMethod <: AbstractMethod end

"""
    MetricMethod <: DissimilarityMethod

A [`DissimilarityMethod`](@ref) that is a true distance: symmetric and
satisfying the triangle inequality, `d(A, C) ≤ d(A, B) + d(B, C)` — a
detour is never shorter than the direct trip. 
Registered in `METRIC_METHODS`, a subset of `DISSIMILARITY_METHODS`.
"""
abstract type MetricMethod <: DissimilarityMethod end

# semimetrics (no triangle inequality)

"""
    SqEuclideanMethod <: DissimilarityMethod

Squared Euclidean distance (`"type" => "sqeuclidean"`) — the canonical
k-means objective. A semimetric, not a true metric: squaring breaks the
triangle inequality.
"""
@kwarg struct SqEuclideanMethod <: DissimilarityMethod end

"""
    WeightedSqEuclideanMethod <: DissimilarityMethod

Squared Euclidean distance with one positive weight per coordinate
(`"type" => "weighted_sqeuclidean"`); `weights` must match the card's
`inputs` in length and order. A semimetric, like the unweighted version.
"""
@kwarg struct WeightedSqEuclideanMethod <: DissimilarityMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

# true metrics

"""
    EuclideanMethod <: MetricMethod

Euclidean distance (`"type" => "euclidean"`).
"""
@kwarg struct EuclideanMethod <: MetricMethod end

"""
    CityblockMethod <: MetricMethod

City-block / Manhattan distance (`"type" => "cityblock"`): the sum of
absolute coordinate differences.
"""
@kwarg struct CityblockMethod <: MetricMethod end

"""
    ChebyshevMethod <: MetricMethod

Chebyshev distance (`"type" => "chebyshev"`): the largest absolute
coordinate difference.
"""
@kwarg struct ChebyshevMethod <: MetricMethod end

"""
    MinkowskiMethod <: MetricMethod

Minkowski distance of order `p` (`"type" => "minkowski"`): the p-norm of
the coordinate differences, interpolating between city block (`p = 1`),
Euclidean (`p = 2`) and Chebyshev (`p → ∞`). Restricted to `p ≥ 1` —
fractional orders break the triangle inequality, and with it the
`MetricMethod` classification.
"""
@kwarg struct MinkowskiMethod <: MetricMethod
    p::Float64 = 2.0 & (dashi = json_number(minimum = 1),)
end

"""
    WeightedEuclideanMethod <: MetricMethod

Euclidean distance with one positive weight per coordinate
(`"type" => "weighted_euclidean"`); `weights` must match the card's
`inputs` in length and order.
"""
@kwarg struct WeightedEuclideanMethod <: MetricMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

"""
    WeightedCityblockMethod <: MetricMethod

City-block distance with one positive weight per coordinate
(`"type" => "weighted_cityblock"`); `weights` must match the card's
`inputs` in length and order.
"""
@kwarg struct WeightedCityblockMethod <: MetricMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

"""
    WeightedMinkowskiMethod <: MetricMethod

Minkowski distance of order `p ≥ 1` with one positive weight per
coordinate (`"type" => "weighted_minkowski"`); `weights` must match the
card's `inputs` in length and order.
"""
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

"""
    METRIC_METHODS

Registry of the [`MetricMethod`](@ref) types by JSON `"type"` name — the
subset of [`DISSIMILARITY_METHODS`](@ref) a metric-restricted field (e.g.
dbscan's) accepts, in parsing and in the generated schema alike.
"""
const METRIC_METHODS = OrderedDict{String, Type}(
    "euclidean" => EuclideanMethod,
    "cityblock" => CityblockMethod,
    "chebyshev" => ChebyshevMethod,
    "minkowski" => MinkowskiMethod,
    "weighted_euclidean" => WeightedEuclideanMethod,
    "weighted_cityblock" => WeightedCityblockMethod,
    "weighted_minkowski" => WeightedMinkowskiMethod,
)

"""
    DISSIMILARITY_METHODS

Registry of every [`DissimilarityMethod`](@ref) type by JSON `"type"` name:
the semimetrics plus all of [`METRIC_METHODS`](@ref). This is the set an
unrestricted dissimilarity field (e.g. k-means') accepts.
"""
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
