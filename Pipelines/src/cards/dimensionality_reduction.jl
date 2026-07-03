abstract type ProjectionMethod end

struct PCAMethod <: ProjectionMethod end

(::PCAMethod)(X, n) = fit(PCA, X; maxoutdim = n)

@kwarg struct PPCAMethod <: ProjectionMethod
    iterations::Int = 1000 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
end

(m::PPCAMethod)(X, n) = fit(PPCA, X; maxoutdim = n, maxiter = m.iterations, m.tol)

@kwarg struct FactorAnalysisMethod <: ProjectionMethod
    iterations::Int = 1000 & (dashi = StringDict("minimum" => 1),)
    tol::Float64 = 1.0e-6 & (dashi = StringDict("exclusiveMinimum" => 0),)
end

(m::FactorAnalysisMethod)(X, n) = fit(FactorAnalysis, X; maxoutdim = n, maxiter = m.iterations, m.tol)

struct MDSMethod <: ProjectionMethod end

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
    method::String
    projector::ProjectionMethod
    inputs::Vector{String}
    partition::Union{String, Nothing}
    n_components::Int
    output::String
end

function get_metadata(drc::DimensionalityReductionCard)
    return StringDict(
        "type" => drc.type,
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
    method::String = c["method"]
    method_options::StringDict = extract_options(c, "method", method)
    projector::ProjectionMethod = construct(PROJECTION_METHODS[method], method_options)
    inputs::Vector{String} = c["inputs"]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    n_components::Int = c["n_components"]
    output::String = get(c, "output", "component")
    return DimensionalityReductionCard(
        type,
        method,
        projector,
        inputs,
        partition,
        n_components,
        output
    )
end

## StandardCard interface

output_vars(drc::DimensionalityReductionCard) = join_names.(drc.output, 1:drc.n_components)

SourceVariables(drc::DimensionalityReductionCard) = SourceVariables(; drc.inputs, drc.partition)

OutputVariables(drc::DimensionalityReductionCard) = OutputVariables(output_vars(drc))

function _train(drc::DimensionalityReductionCard, t, ::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), drc.inputs, dims = 1)
    return drc.projector(X, drc.n_components)
end

function (drc::DimensionalityReductionCard)(model, t, id_var::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), drc.inputs, dims = 1)
    Y = _predict(model, X)
    M, N = size(Y)

    pred_table = SimpleTable(id_var => t[id_var])
    for (i, k) in enumerate(output_vars(drc))
        pred_table[k] = i ≤ M ? Y[i, :] : fill(missing, N)
    end
    return pred_table
end

## UI representation

function CardWidget(
        ::Type{DimensionalityReductionCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(PROJECTION_METHODS))

    fields = vcat(
        [
            Widget("inputs", c),
            Widget("method", c, options = methods),
            Widget("n_components", c),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("partition", c, required = false),
            Widget("output", c, value = "component"),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output", nothing, "n_components"))
end
