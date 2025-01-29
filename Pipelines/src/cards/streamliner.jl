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

const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

function streamlinercard(;
        sorters::AbstractVector{<:AbstractString} = String[],
        predictors::AbstractVector{<:AbstractString} = String[],
        targets::AbstractVector{<:AbstractString} = String[],
        model::AbstractString,
        training::AbstractString,
        suffix::AbstractString = "hat",
        options...
    )

    d = Dict(String(k) => v for (k, v) in pairs(options))

    return StreamlinerCard(;
        sorters,
        predictors,
        targets,
        model_file = joinpath(MODEL_DIR[], model),
        model_params = d,
        training_file = joinpath(TRAINING_DIR[], training),
        training_params = d,
        partition = nothing,
        suffix = suffix
    )
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
