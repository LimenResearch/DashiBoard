const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

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

register_card("streamliner", StreamlinerCard)

function StreamlinerCard(c::AbstractDict)
    order_by::Vector{String} = get(c, :order_by, String[])
    predictors::Vector{String} = get(c, :predictors, String[])
    targets::Vector{String} = get(c, :targets, String[])

    parser = PARSER[]

    model_options = extract_options(c, :model_options, MODEL_OPTIONS_REGEX)
    model = parse_config(Model, parser, MODEL_DIR[], c[:model], model_options)

    training_options = extract_options(c, :training_options, TRAINING_OPTIONS_REGEX)
    training = parse_config(Training, parser, TRAINING_DIR[], c[:training], training_options)

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
        s.partition
    )

    train!(data)

    (; model, training) = s

    return mktempdir() do dir
        result = StreamlinerCore.train(dir, model, data, training)
        path = StreamlinerCore.output_path(dir)
        # TODO: where to keep stats tensor?
        jldopen(path, "a") do file
            file["stats"] = StreamlinerCore.stats_tensor(result, dir)
            file["uvals"] = data.uvals
        end
        content = StreamlinerCore.has_weights(result) ? read(path) : nothing
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

    (; model, training, suffix) = s
    streaming = Streaming(; training.device, training.batchsize)

    return mktempdir() do dir
        path = StreamlinerCore.output_path(dir)
        write(path, state.content)
        uvals = jldopen(path) do file
            file["uvals"]
        end
        partition = nothing

        data = DBData{1}(;
            table = source,
            repository,
            schema,
            s.order_by,
            s.predictors,
            s.targets,
            partition,
            uvals
        )

        StreamlinerCore.evaluate(dir, model, data, streaming; destination, suffix)
    end
end

function list_tomls(dir)
    fls = Iterators.map(splitext, readdir(dir))
    return [f for (f, ext) in fls if ext == ".toml"]
end

function CardWidget(::Type{StreamlinerCard})

    model_tomls = list_tomls(MODEL_DIR[])
    training_tomls = list_tomls(TRAINING_DIR[])

    fields = Widget[
        Widget("model", options = model_tomls),
        Widget("training", options = training_tomls),
        Widget("order_by"),
        Widget("predictors"),
        Widget("targets"),
        Widget("partition"),
        Widget("suffix", value = "hat"),
    ]

    for (idx, m) in enumerate(model_tomls)
        model_config = parsefile(joinpath(MODEL_DIR[], m * ".toml"))
        wdgs = get(model_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, :model, m, idx))
    end

    for (idx, t) in enumerate(training_tomls)
        training_config = parsefile(joinpath(TRAINING_DIR[], t * ".toml"))
        wdgs = get(training_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, :training, t, idx))
    end

    return CardWidget(;
        type = "streamliner",
        label = "Streamliner",
        output = OutputSpec("targets", "suffix"),
        fields
    )
end
