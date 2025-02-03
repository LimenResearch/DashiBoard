const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

to_string_dict(d) = Dict{String, Any}(String(k) => v for (k, v) in d)

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

    parser = PARSER[]

    model_name::String = c.model
    model_file = string(model_name, ".toml")
    model_params = to_string_dict(pairs(c.model_options))
    model = Model(parser, joinpath(MODEL_DIR[], model_file), model_params)

    training_name::String = c.training
    training_file = string(training_name, ".toml")
    training_params = to_string_dict(pairs(c.training_options))
    training = Training(parser, joinpath(TRAINING_DIR[], training_file), training_params)

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

invertible(::StreamlinerCard) = false

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

    return mktemp() do path, io
        result = StreamlinerCore.train(path, model, data, training)
        return CardState(
            content = read(io),
            metadata = to_string_dict(result)
        )
    end
end

# FIXME: implement `evaluate`
