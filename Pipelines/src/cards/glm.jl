to_term(x::String) = Term(Symbol(x))
to_term(x::Number) = ConstantTerm(x)
to_term(x::AbstractVector) = mapfoldl(to_term, *, x)

to_predictors(x::AbstractVector) = mapfoldl(to_term, +, x)
to_target(x::AbstractString) = to_term(x)

const NOISE_MODELS = Dict(
    "normal" => Normal(),
    "binomial" => Binomial(),
    "gamma" => Gamma(),
    "inversegaussian" => InverseGaussian(),
    "poisson" => Poisson(),
)

const LINK_FUNCTIONS = Dict(
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

Run a GLM 
"""
@kwdef struct GLMCard <: AbstractCard
    predictors::Vector{Any} = Any[]
    target::String
    weights::Union{String, Nothing} = nothing
    distribution::String = "normal"
    link::Union{String, Nothing} = nothing
    link_params::Vector{Any} = Any[]
    suffix::String = "hat"
end

to_colnames(::Number) = String[]
to_colnames(s::AbstractString) = String[s]
to_colnames(s::AbstractVector) = reduce(vcat, map(to_colnames, s))

inputs(g::GLMCard) = reduce(vcat, map(to_colnames, g.predictors))

outputs(g::GLMCard) = [g.target]

function evaluate(
        g::GLMCard,
        repo::Repository,
        (source, target)::StringPair;
        schema = nothing
    )

    t = DBInterface.execute(fromtable, repo, From(source); schema)

    formula = to_target(g.target) ~ to_predictors(g.predictors)
    dist = NOISE_MODELS[g.distribution]
    link = isnothing(g.link) ? canonicallink(dist) : LINK_FUNCTIONS[g.link](g.link_params...)
    weights = isnothing(g.weights) ? similar(t[g.target], 0) : t[g.weights]
    model = glm(formula, t, dist, link, wts = weights)
    pred = predict(model)
    pred_name = string(g.target, '_', g.suffix)

    t[pred_name] = pred

    load_table(repo, t, target; schema)
end
