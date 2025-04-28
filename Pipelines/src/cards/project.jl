function _pca(X; maxoutdims = size(X, 1) - 1)
    return fit(PCA, X; maxoutdims)
end

function _ppca(X; maxoutdims = size(X, 1) - 1, iterations = 1000, tol = 1e-6)
    return fit(PPCA, X; maxoutdims, maxiters = iterations, tol)
end

function _factoranalysis(X; maxoutdims = size(X, 1) - 1, iterations = 1000, tol = 1e-6)
    return fit(FactorAnalysis, X; maxoutdims, maxiters = iterations, tol)
end

function _mds(X; maxoutdims = size(X, 1) - 1)
    return fit(MDS, X; maxoutdims)
end

const PROJECTION_FUNCTIONS = OrderedDict{String, Function}(
    "pca" => _pca,
    "ppca" => _ppca,
    "factoranalysis" => _factoranalysis,
    "mds" => _mds,
)

struct Projector
    method::Function
    options::Dict{Symbol, Any}
end

"""
    struct ProjectCard <: AbstractCard
        projector::Projector
        columns::Vector{String}
        partition::Union{String, Nothing}
        output::String
    end

Project `columns` based on `projector`.
Save resulting column as `output`.
"""
struct ProjectCard <: AbstractCard
    projector::Projector
    columns::Vector{String}
    partition::Union{String, Nothing}
    output::String
end