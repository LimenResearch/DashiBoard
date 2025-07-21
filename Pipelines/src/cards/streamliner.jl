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
    c = parsefile(joinpath(dir, file))
    delete!(c, "widgets")
    return T(parser, c, options)
end

"""
    struct StreamlinerCard <: Card
        label::String
        model::Model
        training::Training
        order_by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Run a Streamliner model, predicting `targets` from `inputs`.
"""
struct StreamlinerCard <: StreamingCard
    label::String
    model::Model
    training::Training
    order_by::Vector{String}
    inputs::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
end

const STREAMLINER_CARD_CONFIG = CardConfig{StreamlinerCard}(parse_toml_config("config", "streamliner"))

function StreamlinerCard(c::AbstractDict)
    label::String = card_label(c)

    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{String} = get(c, "inputs", String[])
    targets::Vector{String} = get(c, "targets", String[])

    parser = PARSER[]

    model_options = extract_options(c, "model_options", MODEL_OPTIONS_REGEX)
    model = parse_config(Model, parser, MODEL_DIR[], c["model"], model_options)

    training_options = extract_options(c, "training_options", TRAINING_OPTIONS_REGEX)
    training = parse_config(Training, parser, TRAINING_DIR[], c["training"], training_options)

    partition = get(c, "partition", nothing)
    suffix = get(c, "suffix", "hat")

    return StreamlinerCard(
        label,
        model,
        training,
        order_by,
        inputs,
        targets,
        partition,
        suffix
    )
end

## StreamingCard interface

sorting_vars(sc::StreamlinerCard) = sc.order_by
grouping_vars(::StreamlinerCard) = String[]
input_vars(sc::StreamlinerCard) = sc.inputs
target_vars(sc::StreamlinerCard) = sc.targets
weight_var(::StreamlinerCard) = nothing
partition_var(sc::StreamlinerCard) = sc.partition
output_vars(sc::StreamlinerCard) = join_names.(sc.targets, sc.suffix)

function train(
        repository::Repository,
        sc::StreamlinerCard,
        source::AbstractString;
        schema = nothing
    )

    data = DBData{2}(;
        table = source,
        repository,
        schema,
        sc.order_by,
        sc.inputs,
        sc.targets,
        sc.partition
    )

    train!(data)

    (; model, training) = sc

    return mktempdir() do dir
        result = StreamlinerCore.train(dir, model, data, training)
        path = StreamlinerCore.output_path(dir)
        # TODO: where to keep stats tensor?
        jldopen(path, "a") do file
            file["stats"] = StreamlinerCore.stats_tensor(result, dir)
            file["uvals"] = data.uvals
        end
        content = StreamlinerCore.has_weights(result) ? read(path) : nothing
        metadata = make(StringDict, result)
        return CardState(; content, metadata)
    end
end

function evaluate(
        repository::Repository,
        sc::StreamlinerCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractString;
        schema = nothing
    )

    isnothing(state.content) && throw(ArgumentError("Invalid state"))

    (; model, training, suffix) = sc
    streaming = Streaming(; training.device, training.batchsize)

    mktempdir() do dir
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
            sc.order_by,
            sc.inputs,
            sc.targets,
            partition,
            uvals
        )

        StreamlinerCore.evaluate(dir, model, data, streaming; destination, suffix, id = id_var)
    end
    return
end

function report(::Repository, sc::StreamlinerCard, state::CardState)
    (; loss, metrics) = sc.model
    syms = vcat([metricname(loss)], collect(Symbol, metricname.(metrics)))
    names = string.(syms)
    stats = jlddeserialize(state.content, "stats")
    training = Dict(zip(names, stats[:, 1, end]))
    validation = Dict(zip(names, stats[:, 2, end]))
    return Dict("training" => training, "validation" => validation)
end

## UI representation

function list_tomls(dir)
    fls = Iterators.map(splitext, readdir(dir))
    return [f for (f, ext) in fls if ext == ".toml"]
end

function CardWidget(config::CardConfig{StreamlinerCard}, ::AbstractDict)

    model_tomls = list_tomls(MODEL_DIR[])
    training_tomls = list_tomls(TRAINING_DIR[])

    fields = Widget[
        Widget("model", config.widget_types, options = model_tomls),
        Widget("training", config.widget_types, options = training_tomls),
        Widget("order_by"),
        Widget("inputs"),
        Widget("targets"),
        Widget("partition"),
        Widget("suffix", value = "hat"),
    ]

    for (idx, m) in enumerate(model_tomls)
        model_config = parsefile(joinpath(MODEL_DIR[], m * ".toml"))
        wdgs = get(model_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, "model", m, idx))
    end

    for (idx, t) in enumerate(training_tomls)
        training_config = parsefile(joinpath(TRAINING_DIR[], t * ".toml"))
        wdgs = get(training_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, "training", t, idx))
    end

    return CardWidget(config.key, config.label, fields, OutputSpec("targets", "suffix"))
end
