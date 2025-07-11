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
struct GLMCard <: Card
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

invertible(::GLMCard) = false

isterm(x::AbstractTerm) = x isa Term
predictors(g::GLMCard) = Iterators.map(termnames, Iterators.filter(isterm, terms(g.formula.rhs)))
target(g::GLMCard) = termnames(g.formula.lhs)

inputs(g::GLMCard)::Vector{String} = stringlist(predictors(g), target(g), g.weights, g.partition)
outputs(g::GLMCard)::Vector{String} = [join_names(target(g), g.suffix)]

function train(
        repository::Repository,
        g::GLMCard,
        source::AbstractString;
        schema = nothing
    )

    q = From(source) |> filter_partition(g.partition)
    t = DBInterface.execute(fromtable, repository, q; schema)

    (; formula, distribution, link) = g
    # `weights` cannot yet be passed as a symbol
    weights = isnothing(g.weights) ? similar(t[target(g)], 0) : t[g.weights]
    # TODO save slim version with no data
    m = fit(GeneralizedLinearModel, formula, t, distribution, link, wts = weights)
    return CardState(
        content = jldserialize(m)
    )
end

function evaluate(
        repository::Repository,
        g::GLMCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    model = jlddeserialize(state.content)

    t = DBInterface.execute(fromtable, repository, From(source); schema)

    pred_name = join_names(target(g), g.suffix)
    t[pred_name] = predict(model, t)

    return load_table(repository, t, destination; schema)
end

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
