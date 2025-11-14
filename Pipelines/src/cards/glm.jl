product_term(x::Union{String, Number}) = term(x)
product_term(x::AbstractVector) = mapfoldl(term, *, x)

composite_term(x::AbstractVector) = mapfoldl(product_term, +, x)

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

function model_type end
function has_population end

function get_metadata(gc::AbstractGLMCard)
    metadata = StringDict(
        "type" => gc.type,
        "label" => gc.label,
        "inputs" => gc.inputs,
        "target" => gc.target,
        "weights" => gc.weights,
        "distribution" => gc.distribution_name,
        "link" => gc.link_name,
        "partition" => gc.partition,
        "suffix" => gc.suffix,
    )
    if has_population(gc)
        metadata["population"] = gc.population
        metadata["population_inputs"] = gc.population_inputs
    end
    return metadata
end

function glm_options(c::AbstractDict)
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

    return (; type, label, distribution_name, distribution, link_name, link, weights, partition, suffix)
end

is_linear_model(distribution::Distribution, link::Link) = isa(distribution, Normal) && isa(link, IdentityLink)

function train_glm(gc::AbstractGLMCard, t, LinearModelType, GeneralizedLinearModelType; weights)
    (; formula, distribution, link) = gc
    wts = @something weights similar(t[_target(gc)], 0)
    # TODO save slim version of model with no data
    return if is_linear_model(distribution, link)
        fit(LinearModelType, formula, t, wts = wts)
    else
        fit(GeneralizedLinearModelType, formula, t, distribution, link, wts = wts)
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

has_population(::GLMCard) = false

function GLMCard(c::AbstractDict)
    options = glm_options(c)
    inputs::Vector{Any} = c["inputs"]
    target::String = c["target"]
    rhs = composite_term(inputs)
    lhs = term(target)
    formula::FormulaTerm = lhs ~ rhs
    return GLMCard(
        options.type,
        options.label,
        options.distribution_name,
        options.distribution,
        options.link_name,
        options.link,
        inputs,
        target,
        formula,
        options.weights,
        options.partition,
        options.suffix
    )
end

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
        fixed_effect_terms::Vector{Any}
        random_effect_terms::Vector{Any}
        grouping_factor::String
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
    fixed_effect_terms::Vector{Any}
    random_effect_terms::Vector{Any}
    grouping_factor::String
    target::String
    formula::FormulaTerm
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    suffix::String
end

has_population(::MixedModelCard) = true

function MixedModelCard(c::AbstractDict)
    options = glm_options(c)
    fixed_effect_terms::Vector{Any} = c["fixed_effect_terms"]
    random_effect_terms::Vector{Any} = c["random_effect_terms"]
    grouping_factor::String = c["grouping_factor"]
    target::String = c["target"]
    lhs = term(target)
    rhs = composite_term(fixed_effect_terms) + composite_term(random_effect_terms) | term(grouping_factor)
    formula::FormulaTerm = lhs ~ rhs
    return MixedModelCard(
        options.type,
        options.label,
        options.distribution_name,
        options.distribution,
        options.link_name,
        options.link,
        fixed_effect_terms,
        random_effect_terms,
        grouping_factor,
        target,
        formula,
        options.weights,
        options.partition,
        options.suffix
    )
end

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

function CardWidget(config::CardConfig{GLMCard}, c::AbstractDict)
    noise_models = collect(keys(NOISE_MODELS))
    link_functions = collect(keys(LINK_TYPES))

    fields = [
        Widget("inputs", c),
        Widget("target", c),
        Widget("weights", c, required = false),
        Widget("distribution", c, options = noise_models, required = false),
        Widget("link", c, options = link_functions, required = false),
        Widget("partition", c, required = false),
        Widget("suffix", c, value = "hat"),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("target", "suffix"))
end

function CardWidget(config::CardConfig{MixedModelCard}, c::AbstractDict)
    noise_models = collect(keys(NOISE_MODELS))
    link_functions = collect(keys(LINK_TYPES))

    fields = [
        Widget("inputs", c),
        Widget("population", c),
        Widget("population_inputs", c),
        Widget("target", c),
        Widget("weights", c, required = false),
        Widget("distribution", c, options = noise_models, required = false),
        Widget("link", c, options = link_functions, required = false),
        Widget("partition", c, required = false),
        Widget("suffix", c, value = "hat"),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("target", "suffix"))
end
