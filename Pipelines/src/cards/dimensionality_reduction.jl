function _pca(X, n)
    return fit(PCA, X; maxoutdim = n)
end

function _ppca(X, n; iterations = 1000, tol = 1.0e-6)
    return fit(PPCA, X; maxoutdim = n, maxiter = iterations, tol)
end

function _factoranalysis(X, n; iterations = 1000, tol = 1.0e-6)
    return fit(FactorAnalysis, X; maxoutdim = n, maxiter = iterations, tol)
end

function _mds(X, n)
    return fit(MDS, X; maxoutdim = n, distances = false)
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

function Projector(method_name::AbstractString, d::AbstractDict)
    method = PROJECTION_FUNCTIONS[method_name]
    options = make(SymbolDict, d)
    return Projector(method, options)
end

"""
    struct DimensionalityReductionCard <: Card
        projector::Projector
        columns::Vector{String}
        partition::Union{String, Nothing}
        n_components::Int
        output::String
    end

Project `columns` based on `projector`.
Save resulting column as `output`.
"""
struct DimensionalityReductionCard <: StandardCard
    projector::Projector
    columns::Vector{String}
    partition::Union{String, Nothing}
    n_components::Int
    output::String
end

function DimensionalityReductionCard(c::AbstractDict)
    method_name::String = c["method"]
    method_options::StringDict = extract_options(c, "method_options", METHOD_OPTIONS_REGEX)
    projector::Projector = Projector(method_name, method_options)
    columns::Vector{String} = c["columns"]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    n_components::Int = c["n_components"]
    output::String = get(c, "output", "component")
    return DimensionalityReductionCard(
        projector,
        columns,
        partition,
        n_components,
        output
    )
end

## StandardCard interface

sorting_vars(::DimensionalityReductionCard) = String[]
grouping_vars(::DimensionalityReductionCard) = String[]
input_vars(drc::DimensionalityReductionCard) = drc.columns
target_vars(::DimensionalityReductionCard) = String[]
weight_var(::DimensionalityReductionCard) = nothing
partition_var(drc::DimensionalityReductionCard) = drc.partition
output_vars(drc::DimensionalityReductionCard) = join_names.(drc.output, 1:drc.n_components)

function _train(drc::DimensionalityReductionCard, t, _)
    X = stack(Fix1(getindex, t), drc.columns, dims = 1)
    return drc.projector.method(X, drc.n_components; drc.projector.options...)
end

function (drc::DimensionalityReductionCard)(model, t, id)
    X = stack(Fix1(getindex, t), drc.columns, dims = 1)
    Y = _predict(model, X)
    M, N = size(Y)

    pred_table = SimpleTable()
    for (i, k) in enumerate(output_vars(drc))
        pred_table[k] = i ≤ M ? Y[i, :] : fill(missing, N)
    end
    return pred_table, id
end

## UI representation

function CardWidget(::Type{DimensionalityReductionCard})

    method_names = collect(keys(PROJECTION_FUNCTIONS))

    fields = Widget[
        Widget("method", options = method_names),
        Widget("columns"),
        Widget("n_components"),
        Widget("partition", required = false),
        Widget("output", value = "component"),
    ]

    for (idx, m) in enumerate(method_names)
        method_config = parse_toml_config("dimensionality_reduction", m)
        wdgs = get(method_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, "method", m, idx))
    end

    return CardWidget(;
        type = "dimensionality_reduction",
        output = OutputSpec("output", nothing, "n_components"),
        fields
    )
end
