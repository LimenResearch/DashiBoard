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

choose_projector(d::AbstractDict) = lift_method(d, PROJECTION_METHODS)

@choosetype DashiStyle ProjectionMethod choose_projector

schema_from_type(::Type{ProjectionMethod}) = full_conditional_options_schemas(PROJECTION_METHODS)

StructUtils.lower(::DashiStyle, c::ProjectionMethod) = get_metadata(c, PROJECTION_METHODS)

"""
    @kwarg struct DimensionalityReductionCard{M <: ProjectionMethod} <: StandardCard
        method::M
        inputs::Vector{String}
        partition::Union{String, Nothing} = nothing
        n_components::Int
        output::String = "component"
    end

Project `inputs` based on `method`.
Save resulting column as `output`.
"""
@kwarg struct DimensionalityReductionCard{M <: ProjectionMethod} <: StandardCard
    method::M
    inputs::Vector{String} & (dashi = JSON_NONEMPTY_VARIABLES,)
    partition::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    n_components::Int & (dashi = json_integer(minimum = 1),)
    output::String = "component" & (dashi = json_string(minLength = 1),)
end

DimensionalityReductionCard(c::AbstractDict) = construct(DimensionalityReductionCard, c)

## StandardCard interface

output_vars(drc::DimensionalityReductionCard) = join_names.(drc.output, 1:drc.n_components)

SourceVariables(drc::DimensionalityReductionCard) = SourceVariables(; drc.inputs, drc.partition)

OutputVariables(drc::DimensionalityReductionCard) = OutputVariables(output_vars(drc))

function _train(drc::DimensionalityReductionCard, t, ::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), drc.inputs, dims = 1)
    return drc.method(X, drc.n_components)
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
