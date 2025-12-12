product_term(x::Union{String, Number}) = term(x)
product_term(x::AbstractVector) = mapfoldl(term, *, x)

composite_term(x::AbstractVector) = mapfoldl(product_term, +, x)

function compute_formula(c::AbstractDict)
    inputs = c["inputs"]
    target::String = c["target"]
    lhs = term(target)
    rhs = composite_term(inputs)
    formula::FormulaTerm = lhs ~ rhs
    return inputs, target, formula
end

function compute_mixed_formula(c::AbstractDict)
    fixed_effect_terms::Vector{Any} = c["fixed_effect_terms"]
    random_effect_terms::Vector{Any} = c["random_effect_terms"]
    grouping_factor::String = c["grouping_factor"]
    inputs = MixedInputs(fixed_effect_terms, random_effect_terms, grouping_factor)
    target::String = c["target"]
    lhs = term(target)
    rhs = composite_term(fixed_effect_terms) + composite_term(random_effect_terms) | term(grouping_factor)
    formula::FormulaTerm = lhs ~ rhs
    return inputs, target, formula
end

const NOISE_MODELS = OrderedDict(
    "normal" => Normal(),
    "binomial" => Binomial(),
    "gamma" => Gamma(),
    "inversegaussian" => InverseGaussian(),
    "poisson" => Poisson(),
)

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

abstract type AbstractGLMCard <: StandardCard end

function has_grouping_factor end

struct MixedInputs
    fixed_effect_terms::Vector{Any}
    random_effect_terms::Vector{Any}
    grouping_factor::String
end

function get_metadata(gc::C) where {C <: AbstractGLMCard}
    metadata = StringDict(
        "type" => gc.type,
        "label" => gc.label,
        "target" => gc.target,
        "weights" => gc.weights,
        "distribution" => gc.distribution_name,
        "link" => gc.link_name,
        "partition" => gc.partition,
        "suffix" => gc.suffix,
    )
    if has_grouping_factor(C)
        mi = gc.inputs
        metadata["fixed_effect_terms"] = mi.fixed_effect_terms
        metadata["random_effect_terms"] = mi.random_effect_terms
        metadata["grouping_factor"] = mi.grouping_factor
    else
        metadata["inputs"] = gc.inputs
    end
    return metadata
end

function construct_glm_card(::Type{C}, c::AbstractDict) where {C <: AbstractGLMCard}
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    distribution_name::String = get(c, "distribution", "normal")
    link_name::Union{String, Nothing} = get(c, "link", nothing)
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    distribution::Distribution = NOISE_MODELS[distribution_name]
    link::Link = if isnothing(link_name)
        canonicallink(distribution)
    else
        LINK_TYPES[link_name]()
    end
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")

    inputs, target, formula = has_grouping_factor(C) ? compute_mixed_formula(c) : compute_formula(c)

    return C(
        type, label, distribution_name, distribution, link_name, link,
        inputs, target, formula, weights, partition, suffix
    )
end

is_linear_model(distribution::Distribution, link::Link) = isa(distribution, Normal) && isa(link, IdentityLink)

_fit(args...; weights) = isnothing(weights) ? fit(args...) : fit(args...; wts = weights)

function train_glm(gc::AbstractGLMCard, t, LinearModelType, GeneralizedLinearModelType; weights)
    (; formula, distribution, link) = gc
    # TODO save slim version of model with no data
    return if is_linear_model(distribution, link)
        _fit(LinearModelType, formula, t; weights)
    else
        _fit(GeneralizedLinearModelType, formula, t, distribution, link; weights)
    end
end

## StandardCard interface

isterm(x::AbstractTerm) = x isa Term
_target(gc::AbstractGLMCard) = termnames(gc.formula.lhs)
_output(gc::AbstractGLMCard) = join_names(_target(gc), gc.suffix)

sorting_vars(::AbstractGLMCard) = String[]
grouping_vars(::AbstractGLMCard) = String[]
input_vars(gc::AbstractGLMCard) = termnames.(filter(isterm, terms(gc.formula.rhs)))
target_vars(gc::AbstractGLMCard) = [_target(gc)]
weight_var(gc::AbstractGLMCard) = gc.weights
partition_var(gc::AbstractGLMCard) = gc.partition
output_vars(gc::AbstractGLMCard) = [_output(gc)]

## GLMCard

"""
    struct GLMCard <: Card
      type::String
      label::String
      distribution_name::String
      distribution::Distribution
      link_name::Union{String, Nothing}
      link::Link
      inputs::Vector{Any}
      target::String
      formula::FormulaTerm
      weights::Union{String, Nothing}
      partition::Union{String, Nothing}
      suffix::String
    end

Run a Generalized Linear Model (GLM) based on `formula`.
"""
struct GLMCard <: AbstractGLMCard
    type::String
    label::String
    distribution_name::String
    distribution::Distribution
    link_name::Union{String, Nothing}
    link::Link
    inputs::Vector{Any}
    target::String
    formula::FormulaTerm
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    suffix::String
end

has_grouping_factor(::Type{GLMCard}) = false

GLMCard(c::AbstractDict) = construct_glm_card(GLMCard, c)

_train(gc::GLMCard, t, ::Any; weights = nothing) = train_glm(gc, t, LinearModel, GeneralizedLinearModel; weights)

(gc::GLMCard)(model, t, id) = SimpleTable(_output(gc) => predict(model, t)), id

const GLM_CARD_CONFIG = CardConfig{GLMCard}(parse_toml_config("config", "glm"))

## MixedModelCard

"""
    struct MixedModelCard <: AbstractGLMCard
        type::String
        label::String
        distribution_name::String
        distribution::Distribution
        link_name::Union{String, Nothing}
        link::Link
        inputs::MixedInputs
        target::String
        formula::FormulaTerm
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        suffix::String
    end

Run a Mixed Model based on `formula`.
To use this card, you must load the MixedModels.jl package first.
"""
struct MixedModelCard <: AbstractGLMCard
    type::String
    label::String
    distribution_name::String
    distribution::Distribution
    link_name::Union{String, Nothing}
    link::Link
    inputs::MixedInputs
    target::String
    formula::FormulaTerm
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    suffix::String
end

has_grouping_factor(::Type{MixedModelCard}) = true

MixedModelCard(c::AbstractDict) = construct_glm_card(MixedModelCard, c)

function (gc::MixedModelCard)(model, t, id)
    M = modelmatrix(model)
    col = first(eachcol(M))
    # this column is required, see https://github.com/JuliaStats/MixedModels.jl/issues/626
    t[_target(gc)] = zero(col)
    # TODO: understand what to do with new values of grouping variable (in particular, `predict` vs `simulate`)
    return SimpleTable(_output(gc) => predict(model, t)), id
end

const MIXED_MODEL_CARD_CONFIG = CardConfig{MixedModelCard}(parse_toml_config("config", "mixed_model"))

## UI representation

function CardWidget(config::CardConfig{C}, c::AbstractDict) where {C <: AbstractGLMCard}
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

    return CardWidget(config.key, config.label, fields, OutputSpec("target", "suffix"))
end
