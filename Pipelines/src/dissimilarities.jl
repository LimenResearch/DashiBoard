abstract type DissimilarityMethod <: AbstractMethod end

const DISSIMILARITY_METHODS = OrderedDict{String, Type}(
    "minkowski" => MinkowskiMethod,
    "citiblock" => CitiBlockMethod,
    "weighted_citiblock" => WeightedCitiBlockMethod,
)

# The macro gives automatically
# construct(DissimilarityMethod, d::AbstractDict)
# schema + lowering (for metadata)

@options DissimilarityMethod DISSIMILARITY_METHODS
