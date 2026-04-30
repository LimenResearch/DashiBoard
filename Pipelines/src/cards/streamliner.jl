const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

function parse_without_widgets(dir, x)
    file = string(x, ".toml")
    c = parsefile(joinpath(dir, file))
    delete!(c, "widgets")
    return c
end

function get_streamliner_model(c::AbstractDict, model_name::AbstractString)
    model_options = extract_options(c, "model", model_name)
    model = get(c, "model_metadata") do
        return parse_without_widgets(MODEL_DIR[], model_name)
    end
    return Model(PARSER[], model, model_options)
end

function get_streamliner_training(c::AbstractDict, training_name::AbstractString)
    training_options = extract_options(c, "training", training_name)
    training = get(c, "training_metadata") do
        return parse_without_widgets(TRAINING_DIR[], training_name)
    end
    return Training(PARSER[], training, training_options)
end

"""
    struct StreamlinerCard <: Card
        type::String
        label::String
        model_name::String
        model::Model
        training_name::String
        training::Training
        funnel_name::String
        funnel::Funnel
        partition::Union{String, Nothing}
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
    funnel_name::String
    funnel::Funnel
    partition::Union{String, Nothing}
    suffix::String
end

const STREAMLINER_CARD_CONFIG = CardConfig{StreamlinerCard}(parse_toml_config("config", "streamliner"))

function get_metadata(sc::StreamlinerCard)
    d = StringDict(
        "type" => sc.type,
        "label" => sc.label,
        "model" => sc.model_name,
        "model_metadata" => SC.get_metadata(sc.model),
        "training" => sc.training_name,
        "training_metadata" => SC.get_metadata(sc.training),
        "partition" => sc.partition,
        "suffix" => sc.suffix,
    )
    d["funnel"] = sc.funnel_name
    merge!(d, SC.get_metadata(sc.funnel))
    return d
end

function StreamlinerCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)

    model_name::String = c["model"]
    model = get_streamliner_model(c, model_name)
    training_name::String = c["training"]
    training = get_streamliner_training(c, training_name)
    funnel_name::String = get(c, "funnel", "")
    funnel = PARSER[].funnels[funnel_name](c)

    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")

    return StreamlinerCard(
        type,
        label,
        model_name,
        model,
        training_name,
        training,
        funnel_name,
        funnel,
        partition,
        suffix
    )
end

## StreamingCard interface

sorting_vars(sc::StreamlinerCard) = SC.get_order_by(sc.funnel)
grouping_vars(sc::StreamlinerCard) = String[]
helper_vars(sc::StreamlinerCard) = SC.get_helpers(sc.funnel)

function input_vars(sc::StreamlinerCard)
    return vcat(
        SC.colname.(SC.get_inputs(sc.funnel)),
        SC.get_constant_inputs(sc.funnel),
        to_stringlist(SC.get_input_paths(sc.funnel))
    )
end

function target_vars(sc::StreamlinerCard)
    return vcat(
        SC.colname.(SC.get_targets(sc.funnel)),
        SC.get_constant_targets(sc.funnel),
        to_stringlist(SC.get_target_paths(sc.funnel))
    )
end

weight_var(::StreamlinerCard) = nothing
partition_var(sc::StreamlinerCard) = sc.partition

output_vars(sc::StreamlinerCard) = join_names.(SC.colname.(SC.get_targets(sc.funnel)), sc.suffix)

function train(
        repository::Repository,
        sc::StreamlinerCard,
        source::AbstractString,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    (; model, training, funnel, partition) = sc

    data = FunneledData(
        Val(2), funnel;
        repository, schema, table = source,
        id_var, partition
    )
    SC.compute_unique_values!(data)

    return mktempdir() do dir
        helper_table_names = SC.get_helper_table_names(funnel)
        result = with_table_names(repository, length(helper_table_names); schema) do table_names
            SC.initialize_tables!(data, Dict(helper_table_names .=> table_names))
            SC.train(dir, model, data, training)
        end
        path = SC.output_path(dir)
        # TODO: where to keep stats tensor?
        jldopen(path, "a") do file
            file["stats"] = SC.stats_tensor(result, dir)
            file["unique_values"] = data.unique_values
        end
        content = SC.has_weights(result) ? read(path) : nothing
        metadata = make(StringDict, result)
        return CardState(; content, metadata)
    end
end

function evaluate(
        repository::Repository,
        sc::StreamlinerCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    isnothing(state.content) && throw(ArgumentError("Invalid state"))

    (; model, training, funnel, suffix) = sc
    streaming = Streaming(; training.device, training.batchsize)

    return mktempdir() do dir
        path = SC.output_path(dir)
        write(path, state.content)
        unique_values = jldopen(path) do file
            file["unique_values"]
        end

        data = FunneledData(
            Val(1), funnel;
            repository, schema, table = source,
            id_var, partition = nothing,
            require_targets = false, unique_values
        )

        helper_table_names = SC.get_helper_table_names(funnel)
        with_table_names(repository, length(helper_table_names); schema) do table_names
            SC.initialize_tables!(data, Dict(helper_table_names .=> table_names))
            SC.evaluate(dir, model, data, streaming; destination, suffix)
        end
    end
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

    fields = vcat(
        [
            Widget("order_by", c),
            Widget("inputs", c),
            Widget("targets", c),
            Widget("partition", c),
            Widget("suffix", c, value = "hat"),
        ],
        [
            Widget("model", c, options = collect(keys(model_wdgs))),
        ],
        method_dependent_widgets(c, "model", model_wdgs),
        [
            Widget("training", c, options = collect(keys(training_wdgs))),
        ],
        method_dependent_widgets(c, "training", training_wdgs)
    )

    return CardWidget(config.key, config.label, fields, OutputSpec("targets", "suffix"))
end
