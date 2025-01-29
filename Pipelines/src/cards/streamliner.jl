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
# TODO: consider more complete parsing here?

const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

function fromdict(::Type{StreamlinerCard}, d::AbstractDict)
    sorters = get(d, "sorters", String[])
    predictors = get(d, "predictors", String[])
    targets = get(d, "targets", String[])

    model_file = joinpath(MODEL_DIR[], d["model"])
    model_params = get(d, "model_params", Dict{String, Any}())
    training_file = joinpath(TRAINING_DIR[], d["training"])
    training_params = get(d, "training_params", Dict{String, Any}())

    partition = get(d, "partition", nothing)
    
    return StreamlinerCard(;
        sorters,
        predictors,
        targets,
        model_file,
        model_params,
        training_file,
        training_params,
        partition,
        suffix
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
