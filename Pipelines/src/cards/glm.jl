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

const LINK_FUNCTIONS = OrderedDict(
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
        label::String
        formula::FormulaTerm
        weights::Union{String, Nothing}
        distribution::Distribution
        link::Link
        partition::Union{String, Nothing}
        suffix::String
    end

Run a Generalized Linear Model (GLM) based on `formula`.
"""
struct GLMCard <: StandardCard
    label::String
    formula::FormulaTerm
    weights::Union{String, Nothing}
    distribution::Distribution
    link::Link
    partition::Union{String, Nothing}
    suffix::String
end

const GLM_CARD_CONFIG = CardConfig{GLMCard}(parse_toml_config("config", "glm"))

function GLMCard(c::AbstractDict)
    label::String = card_label(c)
    inputs::Vector{Any} = c["inputs"]
    target::String = c["target"]
    formula::FormulaTerm = to_target(target) ~ to_inputs(inputs)
    weights::Union{String, Nothing} = get(c, "weights", nothing)
    distribution::Distribution = NOISE_MODELS[get(c, "distribution", "normal")]
    link_key::Union{String, Nothing} = get(c, "link", nothing)
    link::Link = if isnothing(link_key)
        canonicallink(distribution)
    else
        LINK_FUNCTIONS[link_key](get(c, "link_params", ())...)
    end
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")

    return GLMCard(label, formula, weights, distribution, link, partition, suffix)
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

function CardWidget(config::CardConfig{GLMCard}, ::AbstractDict)
    noise_models = collect(keys(NOISE_MODELS))
    link_functions = collect(keys(LINK_FUNCTIONS))

    fields = [
        Widget("inputs"),
        Widget("target"),
        Widget("weights", required = false),
        Widget("distribution", config.widget_types, options = noise_models, required = false),
        Widget("link", config.widget_types, options = link_functions, required = false),
        Widget("partition", required = false),
        Widget("suffix", value = "hat"),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("target", "suffix"))
end
