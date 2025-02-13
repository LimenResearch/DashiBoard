const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

to_string_dict(d) = constructfrom(Dict{String, Any}, d)

function parse_config(
        ::Type{T},
        parser::Parser,
        dir::AbstractString,
        name::AbstractString,
        options::AbstractDict
    ) where {T}

    file = string(name, ".toml")
    config = parsefile(joinpath(dir, file))
    delete!(config, "widgets")
    params = to_string_dict(options)
    return T(parser, config, params)
end

"""
    struct StreamlinerCard <: AbstractCard
    model::Model
    training::Training
    order_by::Vector{String}
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
    order_by::Vector{String}
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
end

function StreamlinerCard(c::AbstractDict)
    order_by::Vector{String} = get(c, :order_by, String[])
    predictors::Vector{String} = get(c, :predictors, String[])
    targets::Vector{String} = get(c, :targets, String[])

    parser = PARSER[]

    model = parse_config(Model, parser, MODEL_DIR[], c[:model], c[:model_options])
    training = parse_config(Training, parser, TRAINING_DIR[], c[:training], c[:training_options])

    partition = get(c, :partition, nothing)
    suffix = get(c, :suffix, "hat")

    return StreamlinerCard(
        model,
        training,
        order_by,
        predictors,
        targets,
        partition,
        suffix
    )
end

invertible(::StreamlinerCard) = false

inputs(s::StreamlinerCard) = stringset(s.order_by, s.predictors, s.targets, s.partition)

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
        s.order_by,
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
        s.order_by,
        s.predictors,
        s.targets,
        partition = nothing
    )

    (; model, training, suffix) = s
    streaming = Streaming(; training.device, training.batchsize)

    return mktemp() do path, io
        write(io, state.content)
        flush(io)
        StreamlinerCore.evaluate(path, model, data, streaming; destination, suffix)
    end
end

function list_tomls(dir)
    fls = Iterators.map(splitext, readdir(dir))
    return [f for (f, ext) in fls if ext == ".toml"]
end

function CardWidget(::Type{StreamlinerCard})

    fields = [
        Widget("model", options = list_tomls(MODEL_DIR[])),
        Widget("training", options = list_tomls(TRAINING_DIR[])),
        Widget("order_by"),
        Widget("predictors"),
        Widget("targets"),
        Widget("partition"),
        Widget("suffix", value = "hat"),
    ]

    return CardWidget(;
        type = "streamliner",
        label = "Streamliner",
        output = OutputSpec("targets", "suffix"),
        fields
    )
end
