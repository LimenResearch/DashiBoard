"""
    struct StreamlinerCard <: AbstractCard
        predictors::Vector{String}
        targets::Vector{String}
        model_file::String
        model_params::Dict{String, Any}
        training_file::String
        training_params::Dict{String, Any}
        suffix::String = "hat"
    end

Run a Streamliner model, predicting `targets` from `predictors`. 
"""
@kwdef struct StreamlinerCard <: AbstractCard
    predictors::Vector{String}
    targets::Vector{String}
    model_file::String
    model_params::Dict{String, Any}
    training_file::String
    training_params::Dict{String, Any}
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

inputs(s::StreamlinerCard) = stringset(s.predictors, s.targets, s.partition)

outputs(s::StreamlinerCard) = stringset(join_names.(s.targets, s.suffix))


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