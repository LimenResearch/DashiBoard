"""
    DissimilarityMethod <: AbstractMethod

Configuration of a dissimilarity between feature vectors, selected in JSON
by `"type"` (e.g. `{"type": "minkowski", "p": 3}`) like any other method.
Each concrete type implements [`get_dissimilarity`](@ref), and cards carry
one as a typed field (see `KMeansMethod`), so its options are part of the
card schema and travel with the card.
"""
abstract type DissimilarityMethod <: AbstractMethod end

@kwarg struct SqEuclideanMethod <: DissimilarityMethod end

@kwarg struct EuclideanMethod <: DissimilarityMethod end

@kwarg struct CityblockMethod <: DissimilarityMethod end

@kwarg struct WeightedCityblockMethod <: DissimilarityMethod
    weights::Vector{Float64} & (
        dashi = json_array(items = json_number(exclusiveMinimum = 0), minItems = 1),
    )
end

@kwarg struct MinkowskiMethod <: DissimilarityMethod
    p::Float64 = 2.0 & (dashi = json_number(exclusiveMinimum = 0),)
end

"""
    get_dissimilarity(m::DissimilarityMethod)

The Distances.jl object a `DissimilarityMethod` configures — usable
everywhere the Distances API is (`pairwise`, the `distance` keyword of
`kmeans`, ...), keeping its optimized evaluation paths.
"""
get_dissimilarity(::SqEuclideanMethod) = SqEuclidean()
get_dissimilarity(::EuclideanMethod) = Euclidean()
get_dissimilarity(::CityblockMethod) = Cityblock()
get_dissimilarity(m::WeightedCityblockMethod) = WeightedCityblock(m.weights)
get_dissimilarity(m::MinkowskiMethod) = Minkowski(m.p)

const DISSIMILARITY_METHODS = OrderedDict{String, Type}(
    "sqeuclidean" => SqEuclideanMethod,
    "euclidean" => EuclideanMethod,
    "cityblock" => CityblockMethod,
    "weighted_cityblock" => WeightedCityblockMethod,
    "minkowski" => MinkowskiMethod,
)

# The macro gives automatically
# construct(DissimilarityMethod, d::AbstractDict)
# schema + lowering (for metadata)

@options DissimilarityMethod DISSIMILARITY_METHODS
