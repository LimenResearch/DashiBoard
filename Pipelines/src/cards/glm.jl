to_term(x::String) = Term(Symbol(x))
to_term(x::Number) = ConstantTerm(x)
to_term(x::AbstractVector) = mapfoldl(to_term, *, x)

to_predictors(x::AbstractVector) = mapfoldl(to_term, +, x)
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
    formula::FormulaTerm
    weights::Union{String, Nothing}
    distribution::Distribution
    link::Link
    partition::Union{String, Nothing}
    suffix::String
end

register_card("glm", GLMCard)

function GLMCard(c::AbstractDict)
    predictors::Vector{Any} = c["predictors"]
    target::String = c["target"]
    formula::FormulaTerm = to_target(target) ~ to_predictors(predictors)
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

    return GLMCard(formula, weights, distribution, link, partition, suffix)
end

## StandardCard interface

isterm(x::AbstractTerm) = x isa Term
_target(gc::GLMCard) = termnames(gc.formula.lhs)
_output(gc::GLMCard) = join_names(_target(gc), gc.suffix)

weights(gc::GLMCard) = gc.weights
sorters(::GLMCard) = String[]
partition(gc) = gc.partition

predictors(gc::GLMCard) = termnames.(filter(isterm, terms(gc.formula.rhs)))
targets(gc::GLMCard) = [_target(gc)]
outputs(gc::GLMCard) = [_output(gc)]

function _train(gc::GLMCard, t; weights, _...)
    (; formula, distribution, link) = gc
    wts = @something weights similar(t[_target(gc)], 0)
    # TODO save slim version of model with no data
    return fit(GeneralizedLinearModel, formula, t, distribution, link, wts = wts)
end

(gc::GLMCard)(model, t; id) = SimpleTable(_output(gc) => predict(model, t)), id

## UI representation

function CardWidget(::Type{GLMCard})

    fields = [
        Widget("predictors"),
        Widget("target"),
        Widget("weights", required = false),
        Widget("distribution", options = collect(keys(NOISE_MODELS)), required = false),
        Widget("link", options = collect(keys(LINK_FUNCTIONS)), required = false),
        Widget("partition", required = false),
        Widget("suffix", value = "hat"),
    ]

    return CardWidget(;
        type = "glm",
        label = "GLM",
        output = OutputSpec("target", "suffix"),
        fields
    )
end
