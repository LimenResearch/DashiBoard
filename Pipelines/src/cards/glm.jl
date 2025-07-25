to_term(x::String) = Term(Symbol(x))
to_term(x::Number) = ConstantTerm(x)
to_term(x::AbstractVector) = mapfoldl(to_term, *, x)

to_inputs(x::AbstractVector) = mapfoldl(to_term, +, x)
to_target(x::AbstractString) = to_term(x)

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
struct GLMCard <: StandardCard
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

const GLM_CARD_CONFIG = CardConfig{GLMCard}(parse_toml_config("config", "glm"))

function get_metadata(gc::GLMCard)
    return StringDict(
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
end

function GLMCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    distribution_name::String = get(c, "distribution", "normal")
    link_name::Union{String, Nothing} = get(c, "link", nothing)
    inputs::Vector{Any} = c["inputs"]
    target::String = c["target"]
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    distribution::Distribution = NOISE_MODELS[distribution_name]
    link::Link = if isnothing(link_name)
        canonicallink(distribution)
    else
        LINK_TYPES[link_name]()
    end
    formula::FormulaTerm = to_target(target) ~ to_inputs(inputs)
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")

    return GLMCard(
        type,
        label,
        distribution_name,
        distribution,
        link_name,
        link,
        inputs,
        target,
        formula,
        weights,
        partition,
        suffix
    )
end

## StandardCard interface

isterm(x::AbstractTerm) = x isa Term
_target(gc::GLMCard) = termnames(gc.formula.lhs)
_output(gc::GLMCard) = join_names(_target(gc), gc.suffix)

sorting_vars(::GLMCard) = String[]
grouping_vars(::GLMCard) = String[]
input_vars(gc::GLMCard) = termnames.(filter(isterm, terms(gc.formula.rhs)))
target_vars(gc::GLMCard) = [_target(gc)]
weight_var(gc::GLMCard) = gc.weights
partition_var(gc) = gc.partition
output_vars(gc::GLMCard) = [_output(gc)]

function _train(gc::GLMCard, t, ::Any; weights = nothing)
    (; formula, distribution, link) = gc
    wts = @something weights similar(t[_target(gc)], 0)
    # TODO save slim version of model with no data
    return fit(GeneralizedLinearModel, formula, t, distribution, link, wts = wts)
end

(gc::GLMCard)(model, t, id) = SimpleTable(_output(gc) => predict(model, t)), id

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
