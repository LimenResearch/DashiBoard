"""
    DissimilarityMethod <: AbstractMethod

Configuration of a dissimilarity between feature vectors, selected in JSON
by `"type"` (e.g. `{"type": "minkowski", "p": 3}`) like any other method.
Each concrete type implements [`get_dissimilarity`](@ref), and cards carry
one as a typed field (see `KMeansMethod`), so its options are part of the
card schema and travel with the card.
A dissimilarity promises only a non-negative "how different" score, zero
from a point to itself and symmetric — weaker than a true distance (the
contract of a Distances.jl `SemiMetric`).

The subtype [`MetricMethod`](@ref) marks true metrics: a clustering method
that requires the triangle inequality constrains its field to it, and both
parsing and the generated schema then only accept that subset.
"""
abstract type DissimilarityMethod <: AbstractMethod end

"""
    MetricMethod <: DissimilarityMethod

A [`DissimilarityMethod`](@ref) that is a true distance, additionally
satisfying the triangle inequality, `d(A, C) ≤ d(A, B) + d(B, C)` — a
detour is never shorter than the direct trip (the contract of a
Distances.jl `Metric`).
Registered in `METRIC_METHODS`, a subset of `DISSIMILARITY_METHODS`.
"""
abstract type MetricMethod <: DissimilarityMethod end

abstract type SimpleMetricMethod <: MetricMethod end

abstract type CompositeMetricMethod <: MetricMethod end

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
        dashi = ArrayIR{Float64}(items = NumberIR(exclusiveMinimum = 0), minItems = 1),
    )
end

# true metrics

"""
    EuclideanMethod <: MetricMethod

Euclidean distance (`"type" => "euclidean"`).
"""
@kwarg struct EuclideanMethod <: SimpleMetricMethod end

"""
    CityblockMethod <: SimpleMetricMethod

City-block / Manhattan distance (`"type" => "cityblock"`): the sum of
absolute coordinate differences.
"""
@kwarg struct CityblockMethod <: SimpleMetricMethod end

"""
    ChebyshevMethod <: SimpleMetricMethod

Chebyshev distance (`"type" => "chebyshev"`): the largest absolute
coordinate difference.
"""
@kwarg struct ChebyshevMethod <: SimpleMetricMethod end

"""
    MinkowskiMethod <: SimpleMetricMethod

Minkowski distance of order `p` (`"type" => "minkowski"`): the p-norm of
the coordinate differences, interpolating between city block (`p = 1`),
Euclidean (`p = 2`) and Chebyshev (`p → ∞`). Restricted to `p ≥ 1` —
fractional orders break the triangle inequality, and with it the
metric classification.
"""
@kwarg struct MinkowskiMethod <: SimpleMetricMethod
    p::Float64 = 2.0 & (dashi = NumberIR(minimum = 1),)
end

"""
    WeightedEuclideanMethod <: SimpleMetricMethod

Euclidean distance with one positive weight per coordinate
(`"type" => "weighted_euclidean"`); `weights` must match the card's
`inputs` in length and order.
"""
@kwarg struct WeightedEuclideanMethod <: SimpleMetricMethod
    weights::Vector{Float64} & (
        dashi = ArrayIR{Float64}(items = NumberIR(exclusiveMinimum = 0), minItems = 1),
    )
end

"""
    WeightedCityblockMethod <: SimpleMetricMethod

City-block distance with one positive weight per coordinate
(`"type" => "weighted_cityblock"`); `weights` must match the card's
`inputs` in length and order.
"""
@kwarg struct WeightedCityblockMethod <: SimpleMetricMethod
    weights::Vector{Float64} & (
        dashi = ArrayIR{Float64}(items = NumberIR(exclusiveMinimum = 0), minItems = 1),
    )
end

"""
    WeightedMinkowskiMethod <: SimpleMetricMethod

Minkowski distance of order `p ≥ 1` with one positive weight per
coordinate (`"type" => "weighted_minkowski"`); `weights` must match the
card's `inputs` in length and order.
"""
@kwarg struct WeightedMinkowskiMethod <: SimpleMetricMethod
    weights::Vector{Float64} & (
        dashi = ArrayIR{Float64}(items = NumberIR(exclusiveMinimum = 0), minItems = 1),
    )
    p::Float64 = 2.0 & (dashi = NumberIR(minimum = 1),)
end

"""
    RMSDeviationMethod <: SimpleMetricMethod

RMSDeviation distance (`"type" => "rmsdeviation"`).
"""
@kwarg struct RMSDeviationMethod <: SimpleMetricMethod end

"""
    HellingerDistMethod <: SimpleMetricMethod

HellingerDist distance (`"type" => "hellingerdist"`).
"""
@kwarg struct HellingerDistMethod <: SimpleMetricMethod end

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
get_dissimilarity(::RMSDeviationMethod) = RMSDeviation()
get_dissimilarity(::HellingerDistMethod) = HellingerDist()

"""
    METRIC_METHODS

Registry of the [`MetricMethod`](@ref) types by JSON `"type"` name — the
subset of [`DISSIMILARITY_METHODS`](@ref) a metric-restricted field (e.g.
dbscan's) accepts, in parsing and in the generated schema alike.
"""
const SIMPLE_METRIC_METHODS = OrderedDict{String, Type}(
    "euclidean" => EuclideanMethod,
    "cityblock" => CityblockMethod,
    "chebyshev" => ChebyshevMethod,
    "minkowski" => MinkowskiMethod,
    "weighted_euclidean" => WeightedEuclideanMethod,
    "weighted_cityblock" => WeightedCityblockMethod,
    "weighted_minkowski" => WeightedMinkowskiMethod,
    "rmsdeviation" => RMSDeviationMethod,
    "hellingerdist" => HellingerDistMethod
)

const COMPOSITE_METRIC_METHODS = OrderedDict{String, Type}()

function METRIC_METHODS()
    return merge(SIMPLE_METRIC_METHODS, COMPOSITE_METRIC_METHODS)
end

const NONMETRIC_METHODS = OrderedDict{String, Type}(
    "sqeuclidean" => SqEuclideanMethod,
    "weighted_sqeuclidean" => WeightedSqEuclideanMethod,
)

"""
    DISSIMILARITY_METHODS

Registry of every [`DissimilarityMethod`](@ref) type by JSON `"type"` name:
it includes `NONMETRIC_METHODS` and [`METRIC_METHODS`](@ref). This is the set an
unrestricted dissimilarity field (e.g. k-means') accepts.
"""
function DISSIMILARITY_METHODS()
    return merge(NONMETRIC_METHODS, METRIC_METHODS())
end

# The macro gives automatically
# construct(DissimilarityMethod, d::AbstractDict)
# schema + lowering (for metadata)

@options DissimilarityMethod DISSIMILARITY_METHODS
@options MetricMethod METRIC_METHODS
@options SimpleMetricMethod SIMPLE_METRIC_METHODS
@options CompositeMetricMethod COMPOSITE_METRIC_METHODS
