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
    funnel::F & (
        # TODO: make schema more specific
        dashi = EmptyTaggedObjectIR(
            objects = PARSER[].funnels,
            default_option = "",
            additionalProperties = true
        ),
    )
    partition::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    suffix::String = "hat" & (dashi = StringIR(minLength = 1),)
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
        content = SC.has_weights(result) ? read(path) : nothing
        metadata = to_config(result)
        stats = SC.stats_tensor(result, dir)
        unique_values = data.unique_values
        return (; content, metadata, stats, unique_values)
    end
end

function evaluate(
        repository::Repository,
        sc::StreamlinerCard,
        (; content, metadata, unique_values),
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    isnothing(content) && throw(ArgumentError("Model was not successfully trained"))

    (; model, training, funnel, suffix) = sc
    streaming = Streaming(; training.device, training.batchsize)
    table_spec = SC.TableSpec(; repository, schema, table = source, id_var)

    return mktempdir() do dir
        path = SC.output_path(dir)
        write(path, content)

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
                SC.evaluate(dir, model, data, streaming; destination, suffix)
            end
        end
    end
end

function report(::Repository, sc::StreamlinerCard, (; stats))
    (; loss, metrics) = sc.model
    syms = vcat([metricname(loss)], collect(Symbol, metricname.(metrics)))
    names = string.(syms)
    training = Dict(zip(names, stats[:, 1, end]))
    validation = Dict(zip(names, stats[:, 2, end]))
    return Dict("training" => training, "validation" => validation)
end
