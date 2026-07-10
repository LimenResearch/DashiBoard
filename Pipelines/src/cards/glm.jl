function israndomeffect end

product_term(x::Union{String, Number}) = term(x)
product_term(x::AbstractVector) = mapfoldl(term, *, x)

composite_term(x::AbstractVector) = mapfoldl(product_term, +, x)

function formula_schema()
    properties = StringDict(
        "target" => JSON_VARIABLE,
        "inputs" => json_array() # TODO: make more specific
    )
    required = ["target", "inputs"]
    return json_object(; properties, additionalProperties = false, required)
end

function to_term_list(t::AbstractTerm)
    return t isa ConstantTerm ? t.n :
        t isa Term ? termnames(term) :
        t isa InteractionTerm ? termnames(term.terms) :
        throw(ArgumentError("Unsupported term type $(typeof(t))"))
end

function lower_formula(f::FormulaTerm)::StringDict
    rhs = f.rhs isa AbstractTerm ? (f.rhs,) : f.rhs
    target::String = termnames(f.lhs)
    inputs = Any[to_term_list(t) for t in f.rhs]
    return StringDict("inputs" => inputs, "target" => target)
end

function lift_formula(c::AbstractDict)::FormulaTerm
    inputs::Vector{Any} = c["inputs"]
    target::String = c["target"]
    lhs = term(target)
    rhs = composite_term(inputs)
    return lhs ~ rhs
end

function mixed_formula_schema()
    properties = StringDict(
        "target" => JSON_VARIABLE,
        "fixed_effect_terms" => json_array(),
        "random_effect_terms" => json_array(),
        "grouping_factor" => JSON_VARIABLE
    )
    required = ["target", "fixed_effect_terms", "random_effect_terms", "grouping_factor"]
    return json_object(; properties, additionalProperties = false, required)
end

# TODO: fix for multiple terms in one random effect term
function lower_mixed_formula(f::FormulaTerm)::StringDict
    rhs = f.rhs isa AbstractTerm ? (f.rhs,) : f.rhs
    target::String = termnames(f.lhs)
    fixed_effect_terms = Any[to_term_list(t.lhs) for t in rhs if !israndomeffect(t)]
    random_effect_terms = Any[to_term_list(t.lhs) for t in rhs if israndomeffect(t)]
    grouping_factors = Any[termnames(t.rhs) for t in rhs if israndomeffect(t)]
    isempty(grouping_factor) && throw(ArgumentError("No grouping factor found"))
    allequal(grouping_factors) || throw(ArgumentError("Multiple grouping factor found"))
    grouping_factor = first(grouping_factors)
    return StringDict(
        "fixed_effect_terms" => fixed_effect_terms,
        "random_effect_terms" => random_effect_terms,
        "grouping_factor" => grouping_factor,
        "target" => target,
    )
end

function lift_mixed_formula(c::AbstractDict)::FormulaTerm
    fixed_effect_terms::Vector{Any} = c["fixed_effect_terms"]
    random_effect_terms::Vector{Any} = c["random_effect_terms"]
    grouping_factor::String = c["grouping_factor"]
    target::String = c["target"]
    lhs = term(target)
    rhs = composite_term(fixed_effect_terms) + (composite_term(random_effect_terms) | term(grouping_factor))
    return lhs ~ rhs
end

StructUtils.structlike(::DashiStyle, ::Type{<:FormulaTerm}) = false

const NOISE_MODELS = OrderedDict(
    "normal" => Normal(),
    "binomial" => Binomial(),
    "gamma" => Gamma(),
    "inversegaussian" => InverseGaussian(),
    "poisson" => Poisson(),
)

function StructUtils.lift(::DashiStyle, ::Type{Distribution}, k::AbstractString)
    return NOISE_MODELS[k], nothing
end

StructUtils.lower(::DashiStyle, d::Distribution) = findfirst(==(d), NOISE_MODELS)

const LINK_TYPES = OrderedDict(
    "cauchit" => CauchitLink,
    "cloglog" => CloglogLink,
    "identity" => IdentityLink,
    "inverse" => InverseLink,
    "inversesquare" => InverseSquareLink,
    "logit" => LogitLink,
    "log" => LogLink,
    "negativebinomial" => NegativeBinomialLink,
    "probit" => ProbitLink,
    "sqrt" => SqrtLink,
)

function StructUtils.lift(::DashiStyle, ::Type{Link}, k::AbstractString)
    return LINK_TYPES[k](), nothing
end

function StructUtils.lower(::DashiStyle, l::Link)
    return findfirst(Fix1(isa, l), LINK_TYPES)
end

abstract type AbstractGLMCard <: StandardCard end

function has_grouping_factor end

struct MixedInputs
    fixed_effect_terms::Vector{Any}
    random_effect_terms::Vector{Any}
    grouping_factor::String
end

is_linear_model(distribution::Distribution, link::Link) = isa(distribution, Normal) && isa(link, IdentityLink)

_fit(args...; weights) = isnothing(weights) ? fit(args...) : fit(args...; weights)

function train_glm(gc::AbstractGLMCard, t, LinearModelType, GeneralizedLinearModelType; weights)
    (; formula, distribution, link) = gc
    link = @something link canonicallink(distribution)
    # TODO save slim version of model with no data
    return if is_linear_model(distribution, link)
        _fit(LinearModelType, formula, t; weights)
    else
        _fit(GeneralizedLinearModelType, formula, t, distribution, link; weights)
    end
end

## StandardCard interface

isterm(x::AbstractTerm) = x isa Term
target_var(gc::AbstractGLMCard) = termnames(gc.formula.lhs)
output_var(gc::AbstractGLMCard) = join_names(target_var(gc), gc.suffix)

function SourceVariables(gc::AbstractGLMCard)
    return SourceVariables(;
        inputs = termnames.(filter(isterm, terms(gc.formula.rhs))),
        targets = [target_var(gc)],
        gc.weights, gc.partition
    )
end

OutputVariables(gc::AbstractGLMCard) = OutputVariables([output_var(gc)])

## GLMCard

"""
    struct GLMCard <: Card
        distribution::Distribution = Normal()
        link::Union{Link, Nothing} = nothing
        formula::FormulaTerm
        weights::Union{String, Nothing} = nothing
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Run a Generalized Linear Model (GLM) based on `formula`.
"""
@kwarg struct GLMCard <: AbstractGLMCard
    distribution::Distribution = Normal() & (dashi = json_string(enum = keys(NOISE_MODELS)),)
    link::Union{Link, Nothing} = nothing & (dashi = json_string(enum = keys(LINK_TYPES)),)
    formula::FormulaTerm & (
        dashi = formula_schema(),
        lift = lift_formula,
        lower = lower_formula,
    )
    weights::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    partition::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    suffix::String = "hat" & (dashi = json_string(minLength = 1),)
end

has_grouping_factor(::Type{GLMCard}) = false

GLMCard(c::AbstractDict) = construct(GLMCard, c)

function _train(gc::GLMCard, t, ::AbstractPrimaryKey)
    weights = isnothing(gc.weights) ? nothing : fweights(t[gc.weights])
    return train_glm(gc, t, LinearModel, GeneralizedLinearModel; weights)
end

function (gc::GLMCard)(model, t, id_var::AbstractPrimaryKey)
    return SimpleTable(id_var => t[id_var], output_var(gc) => predict(model, t))
end

## MixedModelCard

"""
    struct MixedModelCard <: AbstractGLMCard
        distribution::Distribution = Normal()
        link::Union{Link, Nothing} = nothing
        formula::FormulaTerm
        weights::Union{String, Nothing} = nothing
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Run a Mixed Model based on `formula`.
To use this card, you must load the MixedModels.jl package first.
"""
@kwarg struct MixedModelCard <: AbstractGLMCard
    distribution::Distribution = Normal() & (dashi = json_string(enum = keys(NOISE_MODELS)),)
    link::Union{Link, Nothing} = nothing & (dashi = json_string(enum = keys(LINK_TYPES)),)
    formula::FormulaTerm & (
        dashi = mixed_formula_schema(),
        lift = lift_mixed_formula,
        lower = lower_mixed_formula,
    )
    weights::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    partition::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    suffix::String = "hat" & (dashi = json_string(minLength = 1),)
end

has_grouping_factor(::Type{MixedModelCard}) = true

MixedModelCard(c::AbstractDict) = construct(MixedModelCard, c)

function (gc::MixedModelCard)(model, t, id_var::AbstractPrimaryKey)
    M = modelmatrix(model)
    col = first(eachcol(M))
    # this column is required, see https://github.com/JuliaStats/MixedModels.jl/issues/626
    t[target_var(gc)] = zero(col)
    # TODO: understand what to do with new values of grouping variable (in particular, `predict` vs `simulate`)
    return SimpleTable(id_var => t[id_var], output_var(gc) => predict(model, t))
end

## UI representation

function CardWidget(
        ::Type{C}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    ) where {C <: AbstractGLMCard}

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    noise_models = collect(keys(NOISE_MODELS))
    link_functions = collect(keys(LINK_TYPES))

    formula_fields = if has_grouping_factor(C)
        [
            Widget("fixed_effect_terms", c),
            Widget("random_effect_terms", c),
            Widget("grouping_factor", c),
        ]
    else
        [Widget("inputs", c)]
    end

    additional_fields = [
        Widget("target", c),
        Widget("weights", c, required = false),
        Widget("distribution", c, options = noise_models, required = false),
        Widget("link", c, options = link_functions, required = false),
        Widget("partition", c, required = false),
        Widget("suffix", c, value = "hat"),
    ]

    fields = vcat(formula_fields, additional_fields)

    return CardWidget(key, fields, OutputSpec("target", "suffix"))
end
