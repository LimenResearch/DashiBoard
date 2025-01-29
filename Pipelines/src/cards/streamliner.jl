"""
    struct StreamlinerCard <: AbstractCard
        sorters::Vector{String}
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
    sorters::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    model_file::String
    model_params::Dict{String, Any}
    training_file::String
    training_params::Dict{String, Any}
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

inputs(s::StreamlinerCard) = stringset(s.sorters, s.predictors, s.targets, s.partition)

outputs(s::StreamlinerCard) = stringset(join_names.(s.targets, s.suffix))

function train(
        repo::Repository,
        s::StreamlinerCard,
        source::AbstractString;
        schema = nothing
    )

    data = DBData{2}(;
        table = source,
        repository = repo,
        schema,
        s.sorters,
        s.predictors,
        s.targets,
        s.partition,
    )

    parser = default_parser()
    model = Model(parser, s.model_file, s.model_params)
    training = Training(parser, s.training_file, s.training_params)
    return mktemp() do path, _
        StreamlinerCore.train(path, model, data, training)
    end
end
