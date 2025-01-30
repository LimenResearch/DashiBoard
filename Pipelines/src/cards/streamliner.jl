const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

"""
    struct StreamlinerCard <: AbstractCard
    model::Model
    training::Training
    sorters::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

Run a Streamliner model, predicting `targets` from `predictors`. 
"""
struct StreamlinerCard <: AbstractCard
    model::Model
    training::Training
    sorters::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
end

function StreamlinerCard(c::Config)
    sorters::Vector{String} = get(c, :sorters, String[])
    predictors::Vector{String} = get(c, :predictors, String[])
    targets::Vector{String} = get(c, :targets, String[])

    parser = default_parser()

    model_file::String = c.model
    model_params = Dict{String, Any}(String(k) => v for (k, v) in pairs(c.model_options))
    model = Model(parser, joinpath(MODEL_DIR[], model_file), model_params)

    training_file::String = c.training
    training_params = Dict{String, Any}(String(k) => v for (k, v) in pairs(c.training_options))
    model = Training(parser, joinpath(TRAINING_DIR[], training_file), training_params)

    partition = get(c, :partition, nothing)
    suffix = get(c, :suffix, "hat")

    return StreamlinerCard(
        model,
        training,
        sorters,
        predictors,
        targets,
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

    (; model, training) = s
    return mktemp() do path, _
        StreamlinerCore.train(path, model, data, training)
    end
end
