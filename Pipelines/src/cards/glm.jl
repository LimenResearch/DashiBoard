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

function _train(gc::AbstractGLMCard, t, ::Any; weights = nothing)
    (; formula, distribution, link) = gc
    wts = @something weights similar(t[_target(gc)], 0)
    # TODO save slim version of model with no data
    ModelType = model_type(gc)
    return fit(ModelType, formula, t, distribution, link, wts = wts)
end

(gc::AbstractGLMCard)(model, t, id) = SimpleTable(_output(gc) => predict(model, t)), id

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

model_type(::GLMCard) = GeneralizedLinearModel
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

const GLM_CARD_CONFIG = CardConfig{GLMCard}(parse_toml_config("config", "glm"))

## MixedModelCard

sorting_vars(::AbstractGLMCard) = String[]
grouping_vars(::AbstractGLMCard) = String[]
input_vars(gc::AbstractGLMCard) = termnames.(filter(isterm, terms(gc.formula.rhs)))
target_vars(gc::AbstractGLMCard) = [_target(gc)]
weight_var(gc::AbstractGLMCard) = gc.weights
partition_var(gc) = gc.partition
output_vars(gc::AbstractGLMCard) = [_output(gc)]

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
    inputs::Vector{Any}
    population::String
    population_inputs::Vector{Any} # TODO: rename to random effects?
    target::String
    formula::FormulaTerm
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    suffix::String
end

has_population(::MixedModelCard) = true

function MixedModelCard(c::AbstractDict)
    options = glm_options(c)
    inputs::Vector{Any} = c["inputs"]
    population::String = c["population"]
    population_inputs::Vector{Any} = c["population_inputs"]
    target::String = c["target"]
    lhs = term(target)
    rhs = composite_term(inputs) + composite_term(population_inputs) | term(population)
    formula::FormulaTerm = lhs ~ rhs
    return MixedModelCard(
        options.type,
        options.label,
        options.distribution_name,
        options.distribution,
        options.link_name,
        options.link,
        inputs,
        target,
        population,
        population_inputs,
        formula,
        options.weights,
        options.partition,
        options.suffix
    )
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
