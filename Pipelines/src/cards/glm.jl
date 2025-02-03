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
    struct GLMCard <: AbstractCard
        formula::FormulaTerm
        weights::Union{String, Nothing}
        distribution::Distribution
        link::Link
        partition::Union{String, Nothing}
        suffix::String
    end

Run a Generalized Linear Model (GLM) based on `formula`.
"""
struct GLMCard <: AbstractCard
    formula::FormulaTerm
    weights::Union{String, Nothing}
    distribution::Distribution
    link::Link
    partition::Union{String, Nothing}
    suffix::String
end

function GLMCard(c::Config)
    predictors::Vector{Any} = c.predictors
    target::String = c.target
    formula::FormulaTerm = to_target(target) ~ to_predictors(predictors)
    weights::Union{String, Nothing} = get(c, :weights, nothing)
    distribution::Distribution = NOISE_MODELS[get(c, :distribution, "normal")]
    link::Link = if haskey(c, :link)
        link_params = get(c, :link_params, ())
        LINK_FUNCTIONS[c.link](link_params...)
    else
        canonicallink(distribution)
    end
    partition::Union{String, Nothing} = get(c, :partition, nothing)
    suffix::String = get(c, :suffix, "hat")

    return GLMCard(formula, weights, distribution, link, partition, suffix)
end

invertible(::GLMCard) = false

function inputs(g::GLMCard)
    formula_vars = [termnames(t) for t in terms(g.formula) if t isa Term]
    return stringset(formula_vars, g.weights, g.partition)
end

targetname(g::GLMCard) = termnames(g.formula.lhs)

outputs(g::GLMCard) = stringset(join_names(targetname(g), g.suffix))

function train(
        repo::Repository,
        g::GLMCard,
        source::AbstractString;
        schema = nothing
    )

    q = From(source) |> filter_partition(g.partition)
    t = DBInterface.execute(fromtable, repo, q; schema)

    (; formula, distribution, link) = g
    # `weights` cannot yet be passed as a symbol
    weights = isnothing(g.weights) ? similar(t[targetname(g)], 0) : t[g.weights]
    # TODO save slim version with no data
    m = fit(GeneralizedLinearModel, formula, t, distribution, link, wts = weights)
    return CardState(
        content = jldserialize(m)
    )
end

function evaluate(
        repo::Repository,
        g::GLMCard,
        state::CardState,
        (source, dest)::Pair;
        schema = nothing
    )

    model = jlddeserialize(state.content)

    t = DBInterface.execute(fromtable, repo, From(source); schema)

    pred_name = join_names(targetname(g), g.suffix)
    t[pred_name] = predict(model, t)

    load_table(repo, t, dest; schema)
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
