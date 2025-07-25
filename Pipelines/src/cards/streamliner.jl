const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

function parse_without_widgets(dir, x)
    file = string(x, ".toml")
    c = parsefile(joinpath(dir, file))
    delete!(c, "widgets")
    return c
end

function get_streamliner_model(parser::Parser, c::AbstractDict, model_name::AbstractString)
    model_options = extract_options(c, model_name, "model")
    model = get(c, "model_metadata") do
        return parse_without_widgets(MODEL_DIR[], model_name)
    end
    return Model(parser, model, model_options)
end

function get_streamliner_training(parser::Parser, c::AbstractDict, training_name::AbstractString)
    training_options = extract_options(c, training_name, "training")
    training = get(c, "training_metadata") do
        return parse_without_widgets(TRAINING_DIR[], training_name)
    end
    return Training(parser, training, training_options)
end

"""
    struct StreamlinerCard <: Card
        type::String
        label::String
        model_name::String
        model::Model
        training_name::String
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
    type::String
    label::String
    model_name::String
    model::Model
    training_name::String
    training::Training
    order_by::Vector{String}
    inputs::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
end

const STREAMLINER_CARD_CONFIG = CardConfig{StreamlinerCard}(parse_toml_config("config", "streamliner"))

function get_metadata(sc::StreamlinerCard)
    return StringDict(
        "type" => sc.type,
        "label" => sc.label,
        "model" => sc.model_name,
        "model_metadata" => StreamlinerCore.get_metadata(sc.model),
        "training" => sc.training_name,
        "training_metadata" => StreamlinerCore.get_metadata(sc.training),
        "order_by" => sc.order_by,
        "inputs" => sc.inputs,
        "targets" => sc.targets,
        "partition" => sc.partition,
        "suffix" => sc.suffix,
    )
end

function StreamlinerCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)

    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{String} = get(c, "inputs", String[])
    targets::Vector{String} = get(c, "targets", String[])

    parser = PARSER[]

    model_name::String = c["model"]
    model = get_streamliner_model(parser, c, model_name)
    training_name::String = c["training"]
    training = get_streamliner_training(parser, c, training_name)

    partition = get(c, "partition", nothing)
    suffix = get(c, "suffix", "hat")

    return StreamlinerCard(
        type,
        label,
        model_name,
        model,
        training_name,
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

function read_wdgs(dir)
    d = OrderedDict{String, StringDict}()
    for fn in readdir(dir)
        k, ext = splitext(fn)
        ext == ".toml" || continue
        content = parsefile(joinpath(dir, fn))
        d[k] = StringDict("widgets" => get(content, "widgets", []))
    end
    return d
end

function CardWidget(config::CardConfig{StreamlinerCard}, c::AbstractDict)
    model_wdgs = read_wdgs(MODEL_DIR[])
    training_wdgs = read_wdgs(TRAINING_DIR[])

    fields = Widget[
        Widget("model", c, options = collect(keys(model_wdgs))),
        Widget("training", c, options = collect(keys(training_wdgs))),
        Widget("order_by", c),
        Widget("inputs", c),
        Widget("targets", c),
        Widget("partition", c),
        Widget("suffix", c, value = "hat"),
    ]

    append!(fields, method_dependent_widgets(c, model_wdgs, "model"))
    append!(fields, method_dependent_widgets(c, training_wdgs, "training"))

    return CardWidget(config.key, config.label, fields, OutputSpec("targets", "suffix"))
end
