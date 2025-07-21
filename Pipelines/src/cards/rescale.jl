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

struct Rescaler
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

"""
    struct RescaleCard <: Card
        label::String
        by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        partition::Union{String, Nothing}
        suffix::String
        target_suffix::Union{String, Nothing}
    end

Card to rescale one or more columns according to a given `rescaler`.
The supported methods are
- `zscore`,
- `maxabs`,
- `minmax`,
- `log`,
- `logistic`.

The resulting rescaled variable is added to the table under the name
`"\$(originalname)_\$(suffix)"`.
"""
struct RescaleCard <: SQLCard
    label::String
    rescaler::Rescaler
    by::Vector{String}
    inputs::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
    target_suffix::Union{String, Nothing}
end

const RESCALE_CARD_CONFIG = CardConfig{RescaleCard}(parse_toml_config("rescale"))

function RescaleCard(c::AbstractDict)
    label::String = card_label(c)
    method::String = c["method"]
    rescaler::Rescaler = RESCALERS[method]
    by::Vector{String} = get(c, "by", String[])
    inputs::Vector{String} = c["inputs"]
    targets::Vector{String} = get(c, "targets", String[])
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "rescaled")
    target_suffix = get(c, "target_suffix", nothing)
    return RescaleCard(
        label,
        rescaler,
        by,
        inputs,
        targets,
        partition,
        suffix,
        target_suffix,
    )
end

## SQLCard interface

invertible(::RescaleCard) = true

_input_and_target_vars(rc::RescaleCard) = [rc.inputs; rc.targets]

sorting_vars(::RescaleCard) = String[]
grouping_vars(rc::RescaleCard) = rc.by
input_vars(rc::RescaleCard) = rc.inputs
target_vars(rc::RescaleCard) = rc.targets
weight_var(::RescaleCard) = nothing
partition_var(rc::RescaleCard) = rc.partition
output_vars(rc::RescaleCard) = join_names.(_input_and_target_vars(rc), rc.suffix)

_append_suffix(s::AbstractString, suffix) = isnothing(suffix) ? s : join_names(s, suffix)

inverse_input_vars(rc::RescaleCard) = _append_suffix.(join_names.(rc.targets, rc.suffix), rc.target_suffix)
inverse_output_vars(rc::RescaleCard) = _append_suffix.(rc.targets, rc.target_suffix)

function pair_wise_group_by(
        repository::Repository,
        source::AbstractString,
        by::AbstractVector,
        cols::AbstractVector,
        fs...;
        partition::Union{AbstractString, Nothing} = nothing,
        schema = nothing,
    )

    key = Get.(by)
    val = [join_names(col, name) => f(Get(col)) for col in cols for (name, f) in fs]
    query = From(source) |>
        filter_partition(partition) |>
        Group(by = key) |>
        Select(key..., val...) |>
        Order(by = key)
    return DBInterface.execute(fromtable, repository, query; schema)
end

function train(repository::Repository, rc::RescaleCard, source::AbstractString; schema = nothing)
    (; by, rescaler) = rc
    (; stats) = rescaler
    tbl = if isempty(stats)
        SimpleTable()
    else
        vars = _input_and_target_vars(rc)
        pair_wise_group_by(repository, source, by, vars, stats...; schema, rc.partition)
    end
    return CardState(content = jldserialize(tbl))
end

function evaluate(
        repository::Repository,
        rc::RescaleCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractString;
        schema = nothing,
        invert::Bool = false
    )

    (; by, targets, rescaler, suffix) = rc
    (; stats, transform, invtransform) = rescaler

    rescaled = if invert
        inverse_inputs, inverse_outputs = inverse_input_vars(rc), inverse_output_vars(rc)
        @. inverse_outputs => invtransform(targets, inverse_inputs)
    else
        inputs, outputs = _input_and_target_vars(rc), output_vars(rc)
        @. outputs => transform(inputs)
    end

    stats_tbl = jlddeserialize(state.content)

    if isempty(stats)
        selection = vcat([id_var => Agg.row_number()], rescaled)
        query = From(source) |> Partition() |> Select(args = selection)
        replace_table(repository, query, destination; schema)
    else
        with_table(repository, stats_tbl; schema) do tbl_name
            eqs = (.==).(Get.(by), GetStats.(by))
            selection = vcat([id_var => Get(id_var)], rescaled)
            query = From(source) |>
                Partition() |>
                Define(id_var => Agg.row_number()) |>
                LeftJoin("stats" => From(tbl_name); on = Fun.and(eqs...)) |>
                Select(args = selection)
            replace_table(repository, query, destination; schema)
        end
    end
    return
end

## UI representation

function CardWidget(config::CardConfig{RescaleCard})

    options = collect(keys(RESCALERS))
    need_group = String[k for (k, v) in pairs(RESCALERS) if !isempty(v.stats)]

    fields = [
        Widget("method"; options),
        Widget("by", visible = Dict("method" => need_group), required = false),
        Widget("inputs"),
        Widget("targets", required = false),
        Widget("partition", required = false),
        Widget("suffix", value = "rescaled"),
        Widget("target_suffix", value = "", required = false),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("inputs", "suffix"))
end
