## Streamliner Card

"""
    struct StreamlinerCard <: Card
        model::Model
        training::Training
        funnel::Funnel
        partition::Union{String, Nothing}
        suffix::String = "hat"
        select::Union{Vector{String}, Nothing} = nothing
    end

Run a Streamliner model, predicting `targets` from `inputs`.

A model may yield more than a prediction. `select` names the fields to write — every one when it
is left out. The prediction is written under `suffix`, any other field under its own name.
"""
@kwarg struct StreamlinerCard{M <: Model, T <: Training, F <: Funnel} <: StreamingCard
    model::M
    training::T
    funnel::F
    partition::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    suffix::String = "hat" & (dashi = StringIR(minLength = 1),)
    select::Maybe{Vector{String}} = nothing & (
        dashi = ArrayIR{String}(items = StringIR(minLength = 1), minItems = 1),
    )
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

function SourceVariables(sc::StreamlinerCard)
    return SourceVariables(;
        order_by = SC.get_order_by(sc.funnel),
        helpers = SC.get_helpers_in(sc.funnel),
        inputs = input_vars(sc),
        targets = target_vars(sc),
        sc.partition
    )
end

# What the funnel's lists come to once their selectors are resolved, so a form can offer a
# transform for each column without resolving anything itself.
function resolved_lists(sc::StreamlinerCard)
    return StringDict(
        "inputs" => SC.colname.(SC.get_inputs(sc.funnel)),
        "targets" => SC.colname.(SC.get_targets(sc.funnel)),
    )
end

# A model's output fields are this card's products: which there are depends on the model chosen,
# which is the one thing a card with fixed products does not have to say.
products(sc::StreamlinerCard) = String[string(field) for field in SC.output_fields(sc.model)]

# The selected fields renamed over the funnel's targets, plus what the funnel writes beside them —
# row counters for a windowed funnel, nothing for a plain one — which invents its names and so
# carries nothing through.
function output_spec(sc::StreamlinerCard)
    funnel = sc.funnel
    targets = SC.colname.(SC.get_targets(funnel))
    groups = product_groups(targets, selected_products(sc), products(sc), sc.suffix)
    helpers = SC.get_helpers_out(funnel)
    if !isempty(helpers)
        any(g -> g.name == "helpers", groups) &&
            throw(ProductError("A model field named `helpers` collides with the funnel's own product", "select"))
        push!(groups, OutputGroup("helpers", OutputSpec(helpers)))
    end
    return groups
end

# One rule per model configuration: "if this is the model, these are the fields `select` may
# name". The fields are read off the configuration's architecture without building a model, so the
# schema can be served before any is chosen — and a form can offer exactly these.
function DashiBase.constraints(::Type{StreamlinerCard})
    isassigned(SC.MODEL_DIR) || return StringDict[]
    dir = SC.MODEL_DIR[]
    return map(SC.available_streamliner_configs(dir, "model")) do config
        name = get(SC.parse_without_properties(dir, config), "name", nothing)
        fields = String[string(field) for field in SC.output_fields(get(PARSER[].models, name, nothing))]
        StringDict(
            "if" => StringDict(
                "properties" => StringDict(
                    "model" => StringDict("properties" => StringDict("type" => StringDict("const" => config)))
                ),
                "required" => ["model"],
            ),
            "then" => StringDict(
                "properties" => StringDict(
                    "select" => StringDict("items" => json_schema(StringIR(enum = fields)))
                )
            ),
        )
    end
end

function train(
        repository::Repository,
        sc::StreamlinerCard,
        source::AbstractString,
        id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    (; model, training, funnel, partition) = sc
    table_spec = SC.TableSpec(; repository, schema, table = source, id_var)
    data = FunneledData(Val(2), funnel, table_spec; partition)
    SC.compute_unique_values!(data)

    return mktempdir() do dir
        helper_keys = SC.get_helper_table_keys(funnel)
        result = with_table_names(repository, length(helper_keys.tables); schema) do table_names
            with_table_names(repository, length(helper_keys.files); schema, file_based = true) do file_names
                SC.initialize_helper_tables!(
                    data,
                    tables = Dict(helper_keys.tables .=> table_names),
                    files = Dict(helper_keys.files .=> get_scratch_file.(file_names))
                )
                SC.train(dir, model, data, training)
            end
        end
        path = SC.output_path(dir)
        # TODO: where to keep stats tensor?
        jldopen(path, "a") do file
            file["stats"] = SC.stats_tensor(result, dir)
            file["unique_values"] = data.unique_values
        end
        content = SC.has_weights(result) ? read(path) : nothing
        metadata = to_config(result)
        return CardState(; content, metadata)
    end
end

function evaluate(
        repository::Repository,
        sc::StreamlinerCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    isnothing(state.content) && throw(ArgumentError("Invalid state"))

    (; model, training, funnel) = sc
    select = selected_products(sc)
    suffixes = product_suffixes(select, products(sc), sc.suffix)
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

        helper_keys = SC.get_helper_table_keys(funnel)
        with_table_names(repository, length(helper_keys.tables); schema) do table_names
            with_table_names(repository, length(helper_keys.files); schema, file_based = true) do file_names
                SC.initialize_helper_tables!(
                    data,
                    tables = Dict(helper_keys.tables .=> table_names),
                    files = Dict(helper_keys.files .=> get_scratch_file.(file_names))
                )
                SC.evaluate(dir, model, data, streaming, Tuple(Symbol.(select)); destination, suffix = suffixes)
            end
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
