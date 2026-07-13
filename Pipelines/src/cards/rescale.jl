GetStats(name) = Get(name, over = Get.stats)

function GetStats(col, st)
    name = join_names(col, st)
    return GetStats(name)
end

function zscore_transform(col)
    x = Get(col)
    μ = GetStats(col, "mean")
    σ = GetStats(col, "std")
    return @. (x - μ) / σ
end

function zscore_invtransform(col, col′)
    y = Get(col′)
    μ = GetStats(col, "mean")
    σ = GetStats(col, "std")
    return @. μ + σ * y
end

function maxabs_transform(col)
    x = Get(col)
    m = GetStats(col, "maxabs")
    return @. x / m
end

function maxabs_invtransform(col, col′)
    y = Get(col′)
    m = GetStats(col, "maxabs")
    return @. m * y
end

function minmax_transform(col)
    x = Get(col)
    x₀, x₁ = GetStats(col, "min"), GetStats(col, "max")
    return @. (x - x₀) / (x₁ - x₀)
end

function minmax_invtransform(col, col′)
    y = Get(col′)
    x₀, x₁ = GetStats(col, "min"), GetStats(col, "max")
    return @. x₀ + (x₁ - x₀) * y
end

ln(x) = log(x) # for consistency with SQL

function log_transform(col)
    x = Get(col)
    return @. ln(x)
end

function log_invtransform(_, col′)
    y = Get(col′)
    return @. exp(y)
end

function logistic_transform(col)
    x = Get(col)
    return @. 1 / (1 + exp(-x))
end

function logistic_invtransform(_, col′)
    y = Get(col′)
    return @. ln(y / (1 - y))
end

@nonstruct struct Rescaler
    stats::Vector{Pair}
    transform::Base.Callable
    invtransform::Union{Base.Callable, Nothing}
end

const RESCALERS = OrderedDict{String, Rescaler}(
    "zscore" => Rescaler(Pair["mean" => Agg.mean, "std" => Agg.stddev_pop], zscore_transform, zscore_invtransform),
    "maxabs" => Rescaler(Pair["maxabs" => Agg.max ∘ Fun.abs], maxabs_transform, maxabs_invtransform),
    "minmax" => Rescaler(Pair["max" => Agg.max, "min" => Agg.min], minmax_transform, minmax_invtransform),
    "log" => Rescaler(Pair[], log_transform, log_invtransform),
    "logistic" => Rescaler(Pair[], logistic_transform, logistic_invtransform)
)

# TODO: also inv-rescale `target_sigma` for probabilistic models
"""
    struct RescaleCard <: Card
        method::Rescaler
        group_by::Vector{String} = String[]
        inputs::Vector{String}
        targets::Vector{String} = String[]
        partition::Union{String, Nothing} = nothing
        suffix::String = "rescaled"
        target_suffix::Union{String, Nothing} = nothing
    end

Card to rescale one or more columns according to a given `method`.
The supported methods are
- `zscore`,
- `maxabs`,
- `minmax`,
- `log`,
- `logistic`.

The resulting rescaled variable is added to the table under the name
`"\$(originalname)_\$(suffix)"`.
"""
@kwarg struct RescaleCard <: SQLCard
    method::Rescaler & (
        dashi = type_schema(RESCALERS),
        lift = Fix2(lift_simple_method, RESCALERS),
        lower = Fix2(lower_simple_method, RESCALERS),
    )
    group_by::Vector{String} = String[] & (dashi = JSON_VARIABLES,)
    inputs::Vector{String} & (dashi = JSON_VARIABLES,)
    targets::Vector{String} = String[] & (dashi = JSON_VARIABLES,)
    partition::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    suffix::String = "rescaled" & (dashi = json_string(minLength = 1),)
    target_suffix::Union{String, Nothing} = nothing & (dashi = json_string(minLength = 1),)
end

RescaleCard(c::AbstractDict) = construct(RescaleCard, c)

## SQLCard interface

invertible(::RescaleCard) = true

input_and_target_vars(rc::RescaleCard) = [rc.inputs; rc.targets]
output_vars(rc::RescaleCard) = join_names.(input_and_target_vars(rc), rc.suffix)

_append_suffix(s::AbstractString, suffix) = isnothing(suffix) ? s : join_names(s, suffix)
inverse_input_vars(rc::RescaleCard) = _append_suffix.(join_names.(rc.targets, rc.suffix), rc.target_suffix)
inverse_output_vars(rc::RescaleCard) = _append_suffix.(rc.targets, rc.target_suffix)

function SourceVariables(rc::RescaleCard)
    return SourceVariables(;
        rc.group_by,
        rc.inputs,
        inverse_inputs = inverse_input_vars(rc),
        rc.targets, # FIXME: this is not fully clean, they might be needed also in eval mode at times
        rc.partition
    )
end

function OutputVariables(rc::RescaleCard)
    return OutputVariables(output_vars(rc), inverse_output_vars(rc))
end

function pair_wise_group_by(
        repository::Repository,
        source::AbstractString,
        by::AbstractVector,
        cols::AbstractVector,
        fs...;
        partition::Union{AbstractString, Nothing} = nothing,
        schema::Union{AbstractString, Nothing} = nothing,
    )

    key = Get.(by)
    val = [join_names(col, name) => f(Get(col)) for col in cols for (name, f) in fs]
    query = From(source) |>
        filter_training(partition) |>
        Group(by = key) |>
        Select(key..., val...) |>
        Order(by = key)
    return DBInterface.execute(fromtable, repository, query; schema)
end

function train(
        repository::Repository, rc::RescaleCard,
        source::AbstractString, ::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    (; group_by, method) = rc
    (; stats) = method
    tbl = if isempty(stats)
        SimpleTable()
    else
        vars = input_and_target_vars(rc)
        pair_wise_group_by(repository, source, group_by, vars, stats...; schema, rc.partition)
    end
    return CardState(content = jldserialize(tbl))
end

function evaluate(
        repository::Repository,
        rc::RescaleCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing,
        invert::Bool = false
    )
    (; group_by, targets, method, suffix) = rc
    (; stats, transform, invtransform) = method

    rescaled = if invert
        inverse_inputs, inverse_outputs = inverse_input_vars(rc), inverse_output_vars(rc)
        @. inverse_outputs => invtransform(targets, inverse_inputs)
    else
        inputs, outputs = input_and_target_vars(rc), output_vars(rc)
        @. outputs => transform(inputs)
    end

    stats_tbl = jlddeserialize(state.content)
    selection = vcat([id_var => Get(id_var)], rescaled)

    if isempty(stats)
        query = From(source) |> Select(args = selection)
        replace_table(repository, query, destination; schema)
    else
        with_table(repository, stats_tbl; schema) do tbl_name
            eqs = (.==).(Get.(group_by), GetStats.(group_by))
            query = From(source) |>
                LeftJoin("stats" => From(tbl_name); on = Fun.and(eqs...)) |>
                Select(args = selection)
            replace_table(repository, query, destination; schema)
        end
    end
    return map(first, rescaled)
end

## UI representation

function CardWidget(
        ::Type{RescaleCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(RESCALERS))
    need_group = String[k for (k, v) in pairs(RESCALERS) if !isempty(v.stats)]

    fields = [
        Widget("method", c; options = methods),
        Widget("group_by", c, visible = Dict("method" => need_group), required = false),
        Widget("inputs", c),
        Widget("targets", c, required = false),
        Widget("partition", c, required = false),
        Widget("suffix", c, value = "rescaled"),
        Widget("target_suffix", c, value = "", required = false),
    ]

    return CardWidget(key, fields, OutputSpec("inputs", "suffix"))
end
