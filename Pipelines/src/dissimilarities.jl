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
    ConjunctiveMethod <: MetricMethod

Conjunctive distance (`"type" => "conjunctive"`): `blocks` assigns each of
the card's `inputs` to a block, `radii` gives each block its own radius, and
the distance is the largest within-block Euclidean distance divided by that
block's radius. Two points are close only when close in every block at once,
so no exchange rate between the blocks' units is ever asserted — with inputs
`[east, north, minutes]`, `blocks = [1, 1, 2]` and `radii = [5.0, 60.0]`
reads "within 5 km and within 60 minutes". Distances are dimensionless: 1
means "at the radius in the worst block". A maximum of metrics is again a
metric, hence a true [`MetricMethod`](@ref).
"""
@kwarg struct ConjunctiveMethod <: MetricMethod
    blocks::Vector{Int} & (
        dashi = json_array(items = json_integer(minimum = 1), minItems = 1),
    )
    radii::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

"""
    Conjunctive(groups, radii, dims)

The Distances.jl object behind [`ConjunctiveMethod`](@ref): `groups` lists
the coordinate indices of each block, `radii` its radius, `dims` the
coordinate count every evaluated pair must have.
"""
struct Conjunctive <: Metric
    groups::Vector{Vector{Int}}
    radii::Vector{Float64}
    dims::Int
end

function (dist::Conjunctive)(a, b)
    length(a) == length(b) == dist.dims || throw(
        DimensionMismatch(
            "conjunctive metric over $(dist.dims) coordinates, got $(length(a)) and $(length(b))"
        )
    )
    worst = 0.0
    for (g, r) in zip(dist.groups, dist.radii)
        s = 0.0
        @inbounds for k in g
            δ = a[k] - b[k]
            s += δ * δ
        end
        d = sqrt(s) / r
        d > worst && (worst = d)
    end
    return worst
end

# the generic fallback probes the metric on two scalars, which the dimension
# check above refuses
Distances.result_type(::Conjunctive, ::Type, ::Type) = Float64

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

function get_dissimilarity(m::ConjunctiveMethod)
    (; blocks, radii) = m
    sort(unique(blocks)) == eachindex(radii) || throw(
        ArgumentError("`blocks` must number the blocks 1:$(length(radii)), got $(sort(unique(blocks)))")
    )
    all(>(0), radii) || throw(ArgumentError("`radii` must be positive, got $radii"))
    groups = [findall(==(b), blocks) for b in eachindex(radii)]
    return Conjunctive(groups, radii, length(blocks))
end

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
    "conjunctive" => ConjunctiveMethod,
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
