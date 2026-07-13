const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

function available_streamliner_configs(dir)
    return String[
        fn for (fn, ext) in Iterators.map(splitext, readdir(dir)) if ext == ".toml"
    ]
end

function parse_without_widgets(dir, x)
    file = string(x, ".toml")
    c = parsefile(joinpath(dir, file))
    delete!(c, "widgets")
    delete!(c, "properties")
    return c
end

function parse_properties(dir, x)::Vector{StringDict}
    file = string(x, ".toml")
    c = parsefile(joinpath(dir, file))
    return get(c, "properties", StringDict[])
end

## Model, Training, and Funnel implementations

function get_streamliner_model(config::AbstractDict)
    model_name::String = config["type"]
    model = parse_without_widgets(MODEL_DIR[], model_name)
    return Model(PARSER[], model, config)
end

StructUtils.structlike(::DashiStyle, ::Type{<:Model}) = false

function StructUtils.lift(::DashiStyle, ::Type{Model}, d::AbstractDict)
    return if isassigned(MODEL_DIR)
        get_streamliner_model(d), nothing
    else
        Model(PARSER[], d), nothing
    end
end

StructUtils.lower(::DashiStyle, model::Model) = SC.get_metadata(model)

function schema_from_type(::Type{Model})
    return if isassigned(MODEL_DIR)
        conditional_streamliner_schema(MODEL_DIR[], "model")
    else
        json_object() # TODO: here and in `Training` decide more carefull how to distinguish between the two cases
    end
end

function get_streamliner_training(config::AbstractDict)
    training_name::String = config["type"]
    training = parse_without_widgets(TRAINING_DIR[], training_name)
    return Training(PARSER[], training, config)
end

StructUtils.structlike(::DashiStyle, ::Type{<:Training}) = false

function StructUtils.lift(::DashiStyle, ::Type{Training}, d::AbstractDict)
    return if isassigned(TRAINING_DIR)
        get_streamliner_training(d), nothing
    else
        Training(PARSER[], d), nothing
    end
end

StructUtils.lower(::DashiStyle, training::Training) = SC.get_metadata(training)

function schema_from_type(::Type{Training})
    return if isassigned(TRAINING_DIR)
        conditional_streamliner_schema(TRAINING_DIR[], "training")
    else
        json_object()
    end
end

function get_streamliner_funnel(config::AbstractDict)
    funnel_name::String = get(config, "type", "")
    return PARSER[].funnels[funnel_name](config)
end

StructUtils.structlike(::DashiStyle, ::Type{<:Funnel}) = false

function StructUtils.lift(::DashiStyle, ::Type{Funnel}, d::AbstractDict)
    return get_streamliner_funnel(d), nothing
end

function StructUtils.lower(::DashiStyle, funnel::Funnel)
    d = SC.get_metadata(funnel)
    d["type"] = findfirst(Fix1(isa, funnel), PARSER[].funnels)
    return d
end

## Streamliner Card

"""
    struct StreamlinerCard <: Card
        model::Model
        training::Training
        funnel::Funnel
        partition::Union{String, Nothing}
        suffix::String = "hat"
    end

Run a Streamliner model, predicting `targets` from `inputs`.
"""
@kwarg struct StreamlinerCard{M <: Model, T <: Training, F <: Funnel} <: StreamingCard
    model::M
    training::T
    funnel::F & (dashi = type_schema(PARSER[].funnels, additionalProperties = true, default = ""),) # TODO: make more specific
    partition::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    suffix::String = "hat" & (dashi = json_string(minLength = 1),)
end

## StreamingCard interface

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

function output_vars(sc::StreamlinerCard)
    outputs = join_names.(SC.colname.(SC.get_targets(sc.funnel)), sc.suffix)
    return vcat(outputs, SC.get_helpers_out(sc.funnel))
end

function SourceVariables(sc::StreamlinerCard)
    return SourceVariables(;
        order_by = SC.get_order_by(sc.funnel),
        helpers = SC.get_helpers_in(sc.funnel),
        inputs = input_vars(sc),
        targets = target_vars(sc),
        sc.partition
    )
end

OutputVariables(sc::StreamlinerCard) = OutputVariables(output_vars(sc))

function train(
        repository::Repository,
        sc::StreamlinerCard,
        source::AbstractString,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    (; model, training, funnel, partition) = sc
    table_spec = SC.TableSpec(; repository, schema, table = source, id_var)
    data = FunneledData(Val(2), funnel, table_spec; partition)
    SC.compute_unique_values!(data)

    return mktempdir() do dir
        table_keys = SC.get_helper_table_keys(funnel)
        result = with_table_names(repository, length(table_keys); schema) do table_names
            SC.initialize_helper_tables!(data, Dict(table_keys .=> table_names))
            SC.train(dir, model, data, training)
        end
        path = SC.output_path(dir)
        # TODO: where to keep stats tensor?
        jldopen(path, "a") do file
            file["stats"] = SC.stats_tensor(result, dir)
            file["unique_values"] = data.unique_values
        end
        content = SC.has_weights(result) ? read(path) : nothing
        metadata = construct(StringDict, result)
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
    table_spec = SC.TableSpec(; repository, schema, table = source, id_var)

    return mktempdir() do dir
        path = SC.output_path(dir)
        write(path, state.content)
        unique_values = jldopen(path) do file
            file["unique_values"]
        end

        data = FunneledData(
            Val(1), funnel, table_spec;
            partition = nothing, require_targets = false, unique_values
        )

        table_keys = SC.get_helper_table_keys(funnel)
        with_table_names(repository, length(table_keys); schema) do table_names
            SC.initialize_helper_tables!(data, Dict(table_keys .=> table_names))
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

function CardWidget(
        ::Type{StreamlinerCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

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

    return CardWidget(key, fields, OutputSpec("targets", "suffix"))
end
