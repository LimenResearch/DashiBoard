const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

to_string_dict(d) = constructfrom(Dict{String, Any}, d)

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
    model_params = to_string_dict(c.model_options)
    model = Model(parser, joinpath(MODEL_DIR[], model_file), model_params)

    training_name::String = c.training
    training_file = string(training_name, ".toml")
    training_params = to_string_dict(c.training_options)
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
        repository::Repository,
        s::StreamlinerCard,
        source::AbstractString;
        schema = nothing
    )

    data = DBData{2}(;
        table = source,
        repository,
        schema,
        s.sorters,
        s.predictors,
        s.targets,
        s.partition,
    )

    (; model, training) = s

    return mktemp() do path, io
        result = StreamlinerCore.train(path, model, data, training)
        content = StreamlinerCore.has_weights(result) ? read(io) : nothing
        metadata = to_string_dict(result)
        return CardState(; content, metadata)
    end
end

function evaluate(
        repository::Repository,
        s::StreamlinerCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    isnothing(state.content) && throw(ArgumentError("Invalid state"))

    data = DBData{1}(;
        table = source,
        repository,
        schema,
        s.sorters,
        s.predictors,
        s.targets,
        partition = nothing
    )

    (; model, training) = s
    streaming = Streaming(; training.device, training.batchsize)

    return mktemp() do path, io
        write(io, state.content)
        seekstart(io)
        StreamlinerCore.evaluate(path, model, data, streaming)
    end
end
