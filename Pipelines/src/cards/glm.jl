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
        predictors::Vector{Any} = Any[]
        target::String
        weights::Union{String, Nothing} = nothing
        distribution::String = "normal"
        link::Union{String, Nothing} = nothing
        link_params::Vector{Any} = Any[]
        suffix::String = "hat"
    end

Run a Generalized Linear Model (GLM), predicting `target` from `predictors`. 
"""
@kwdef struct GLMCard <: AbstractCard
    predictors::Vector{Any} = Any[]
    target::String
    weights::Union{String, Nothing} = nothing
    distribution::Union{String, Nothing} = nothing
    link::Union{String, Nothing} = nothing
    link_params::Vector{Any} = Any[]
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

to_colnames(::Number) = String[]
to_colnames(s::AbstractString) = String[s]
to_colnames(s::AbstractVector) = reduce(vcat, map(to_colnames, s))

function inputs(g::GLMCard)
    i = OrderedSet{String}()
    for term in g.predictors
        union!(i, to_colnames(term))
    end
    push!(i, g.target)
    isnothing(g.partition) || push!(i, g.partition)
    return i
end

outputs(g::GLMCard) = OrderedSet([string(g.target, '_', g.suffix)])

function train(
        repo::Repository,
        g::GLMCard,
        source::AbstractString;
        schema = nothing
    )

    select = filter_partition(g.partition)
    q = From(source) |> select
    t = DBInterface.execute(fromtable, repo, q; schema)

    formula = to_target(g.target) ~ to_predictors(g.predictors)
    dist = NOISE_MODELS[something(g.distribution, "normal")]
    link = isnothing(g.link) ? canonicallink(dist) : LINK_FUNCTIONS[g.link](g.link_params...)
    weights = isnothing(g.weights) ? similar(t[g.target], 0) : t[g.weights]
    # TODO save slim version with no data
    return fit(GeneralizedLinearModel, formula, t, dist, link, wts = weights)
end

function evaluate(
        repo::Repository,
        g::GLMCard,
        model::RegressionModel,
        (source, dest)::Pair;
        schema = nothing
    )

    t = DBInterface.execute(fromtable, repo, From(source); schema)

    pred_name = string(g.target, '_', g.suffix)
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
