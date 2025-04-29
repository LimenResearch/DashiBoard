function _pca(X; maxoutdims = size(X, 1) - 1)
    return fit(PCA, X; maxoutdims)
end

function _ppca(X; maxoutdims = size(X, 1) - 1, iterations = 1000, tol = 1.0e-6)
    return fit(PPCA, X; maxoutdims, maxiters = iterations, tol)
end

function _factoranalysis(X; maxoutdims = size(X, 1) - 1, iterations = 1000, tol = 1.0e-6)
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
    struct DimensionalityReductionCard <: AbstractCard
        projector::Projector
        columns::Vector{String}
        partition::Union{String, Nothing}
        output::String
    end

Project `columns` based on `projector`.
Save resulting column as `output`.
"""
struct DimensionalityReductionCard <: AbstractCard
    projector::Projector
    columns::Vector{String}
    partition::Union{String, Nothing}
    output::String
end

register_card("dimensionality_reduction", DimensionalityReductionCard)

function CardWidget(::Type{DimensionalityReductionCard})

    method_names = collect(keys(PROJECTION_FUNCTIONS))

    fields = Widget[
        Widget("method", options = method_names),
        Widget("columns"),
        Widget("partition", required = false),
        Widget("output"),
    ]

    for (idx, m) in enumerate(method_names)
        method_config = parsefile(config_path("dimensionality_reduction", m * ".toml"))
        wdgs = get(method_config, "widgets", [])
        append!(fields, generate_widget.(wdgs, :method, m, idx))
    end

    return CardWidget(;
        type = "dimensionality_reduction",
        label = "Dimensionality Reduction",
        # output = OutputSpec("output"), FIXME: correct
        fields
    )
end
