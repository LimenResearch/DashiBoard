abstract type ProjectionMethod end

struct PCAMethod <: ProjectionMethod end

PCAMethod(::AbstractDict) = PCAMethod()

(::PCAMethod)(X, n) = fit(PCA, X; maxoutdim = n)

struct PPCAMethod <: ProjectionMethod
    iterations::Int
    tol::Float64
end

function PPCAMethod(c::AbstractDict)
    iterations::Int = get(c, "iterations", 1000)
    tol::Float64 = get(c, "tol", 1.0e-6)
    return PPCAMethod(iterations, tol)
end

(m::PPCAMethod)(X, n) = fit(PPCA, X; maxoutdim = n, maxiter = m.iterations, m.tol)

struct FactorAnalysisMethod <: ProjectionMethod
    iterations::Int
    tol::Float64
end

function FactorAnalysisMethod(c::AbstractDict)
    iterations::Int = get(c, "iterations", 1000)
    tol::Float64 = get(c, "tol", 1.0e-6)
    return FactorAnalysisMethod(iterations, tol)
end

(m::FactorAnalysisMethod)(X, n) = fit(FactorAnalysis, X; maxoutdim = n, maxiter = m.iterations, m.tol)

struct MDSMethod <: ProjectionMethod end

MDSMethod(::AbstractDict) = MDSMethod()

(mds::MDSMethod)(X, n) = fit(MDS, X; maxoutdim = n, distances = false)

const PROJECTION_METHODS = OrderedDict{String, DataType}(
    "pca" => PCAMethod,
    "ppca" => PPCAMethod,
    "factoranalysis" => FactorAnalysisMethod,
    "mds" => MDSMethod,
)

"""
    struct DimensionalityReductionCard <: Card
        type::String
        label::String
        method::String
        projector::ProjectionMethod
        inputs::Vector{String}
        partition::Union{String, Nothing}
        n_components::Int
        output::String
    end

Project `inputs` based on `projector`.
Save resulting column as `output`.
"""
struct DimensionalityReductionCard <: StandardCard
    type::String
    label::String
    method::String
    projector::ProjectionMethod
    inputs::Vector{String}
    partition::Union{String, Nothing}
    n_components::Int
    output::String
end

const DIMENSIONALITY_REDUCTION_CARD_CONFIG = CardConfig{DimensionalityReductionCard}(
    parse_toml_config("config", "dimensionality_reduction")
)

function get_metadata(drc::DimensionalityReductionCard)
    return StringDict(
        "type" => drc.type,
        "label" => drc.label,
        "method" => drc.method,
        "method_options" => get_options(drc.projector),
        "inputs" => drc.inputs,
        "partition" => drc.partition,
        "n_components" => drc.n_components,
        "output" => drc.output,
    )
end

function DimensionalityReductionCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    method::String = c["method"]
    method_options::StringDict = extract_options(c, "method_options", METHOD_OPTIONS_REGEX)
    projector::ProjectionMethod = PROJECTION_METHODS[method](method_options)
    inputs::Vector{String} = c["inputs"]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    n_components::Int = c["n_components"]
    output::String = get(c, "output", "component")
    return DimensionalityReductionCard(
        type,
        label,
        method,
        projector,
        inputs,
        partition,
        n_components,
        output
    )
end

## StandardCard interface

sorting_vars(::DimensionalityReductionCard) = String[]
grouping_vars(::DimensionalityReductionCard) = String[]
input_vars(drc::DimensionalityReductionCard) = drc.inputs
target_vars(::DimensionalityReductionCard) = String[]
weight_var(::DimensionalityReductionCard) = nothing
partition_var(drc::DimensionalityReductionCard) = drc.partition
output_vars(drc::DimensionalityReductionCard) = join_names.(drc.output, 1:drc.n_components)

function _train(drc::DimensionalityReductionCard, t, _)
    X = stack(Fix1(getindex, t), drc.inputs, dims = 1)
    return drc.projector(X, drc.n_components)
end

function (drc::DimensionalityReductionCard)(model, t, id)
    X = stack(Fix1(getindex, t), drc.inputs, dims = 1)
    Y = _predict(model, X)
    M, N = size(Y)

    pred_table = SimpleTable()
    for (i, k) in enumerate(output_vars(drc))
        pred_table[k] = i ≤ M ? Y[i, :] : fill(missing, N)
    end
    return pred_table, id
end

## UI representation

function CardWidget(config::CardConfig{DimensionalityReductionCard}, c::AbstractDict)
    methods = collect(keys(PROJECTION_METHODS))

    fields = Widget[
        Widget("method", c, options = methods),
        Widget("inputs", c),
        Widget("n_components", c),
        Widget("partition", c, required = false),
        Widget("output", c, value = "component"),
    ]

    append!(fields, method_dependent_widgets(c, config.methods, "method"))

    return CardWidget(config.key, config.label, fields, OutputSpec("output", nothing, "n_components"))
end
