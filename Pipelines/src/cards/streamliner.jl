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
    # A product is written once, so the list is a set.
    select::Maybe{Vector{String}} = nothing & (
        dashi = ArrayIR{String}(items = StringIR(minLength = 1), minItems = 1, uniqueItems = true),
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

"""
    model_issue(repository, sc::StreamlinerCard, table; schema = nothing)

Whether the card's model can be built for what its funnel feeds it: `nothing` if it can, otherwise
`(; message, input, target)` with the sizes one sample has. Nothing is trained and no row is read.
A categorical column of `table` counts as its distinct values, as the model sees it one-hot; a
column `table` does not have yet — an earlier card's output — counts as one, which is what every
card writes. This is what lets Confirm say a model and a funnel do not fit before a run finds out.
"""
function model_issue(
        repository::Repository, sc::StreamlinerCard, table::AbstractString;
        schema::Maybe{AbstractString} = nothing
    )
    table_spec = SC.TableSpec(; repository, schema, table, id_var = "")
    unique_values = categorical_values(repository, sc.funnel, table; schema)
    templates = SC.get_templates(FunneledData(Val(2), sc.funnel, table_spec; partition = nothing, unique_values))
    return try
        sc.model(templates)
        nothing
    catch err
        # Building refuses a shape it cannot handle with these; anything else is not about fit.
        err isa Union{ArgumentError, DimensionMismatch} || rethrow()
        input, target = collect(Int, templates.input.size), collect(Int, templates.target.size)
        reason = err isa ArgumentError ? err.msg : sprint(showerror, err)
        hint = occursin("Could not infer output features", reason) ?
            " The last layer has no size of its own and the target's shape does not give it one: give the last layer a size, or use a model that keeps the target's shape, such as a convolution." :
            ""
        message = "This model cannot be built for this funnel: its input is $(shape_text(input)) and its target $(shape_text(target)). $(reason)$(hint)"
        (; message, input, target)
    end
end

# One sample's size, read as a funnel lays it out: columns last, steps before them.
function shape_text(size::AbstractVector{Int})
    columns = string(last(size), last(size) == 1 ? " column" : " columns")
    length(size) == 1 && return columns
    length(size) == 2 && return string(first(size), first(size) == 1 ? " step × " : " steps × ", columns)
    return join(size, " × ")
end

# The distinct values of the funnel's non-numeric columns that `table` holds, for one-hot sizes.
function categorical_values(
        repository::Repository, funnel::Funnel, table::AbstractString; schema::Maybe{AbstractString}
    )
    found = DBInterface.execute(Tables.schema, repository, From(table); schema)
    names = union(SC.colname.(SC.get_inputs(funnel)), SC.colname.(SC.get_targets(funnel)))
    values = Dict{String, AbstractVector}()
    for name in names
        i = findfirst(==(Symbol(name)), collect(found.names))
        (isnothing(i) || nonmissingtype(found.types[i]) <: Number) && continue
        query = From(table) |> Group(Get(name)) |> Select(Get(name)) |> Order(Get(name))
        values[name] = DBInterface.execute(Fix1(map, first), repository, query; schema)
    end
    return values
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

function no_model_message(sc::StreamlinerCard, state::CardState)
    get(state.metadata, "trained", false) === true || return "this card has not been trained."
    cause = isnothing(sc.partition) ?
        "the card has no `partition`, so no rows were set aside to validate on. Set `partition` to a " *
        "column that is 1 for the rows to train on and 2 for the rows to validate on, such as a split card writes" :
        "the loss on the rows `$(sc.partition)` marks 2 never improved. Check that such rows exist " *
        "and that the inputs are on comparable scales"
    return "training kept no model to predict with: $(cause)."
end

function evaluate(
        repository::Repository,
        sc::StreamlinerCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    # No model means either the card was never trained, or it was and training kept none: a model
    # is kept only if its loss on the validation rows improved. The training metadata tells the two
    # apart, and the second has a cause the author can act on.
    isnothing(state.content) && throw(ArgumentError(no_model_message(sc, state)))

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
