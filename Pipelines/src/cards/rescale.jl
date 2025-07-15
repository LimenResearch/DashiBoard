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
        rescaler::Rescaler
        by::Vector{String} = String[]
        columns::Vector{String}
        suffix::String = "rescaled"
    end

Card to rescale of one or more columns according to a given `rescaler`.
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
    rescaler::Rescaler
    by::Vector{String}
    columns::Vector{String}
    inverse_columns::Dict{String, String}
    partition::Union{String, Nothing}
    suffix::String
end

function RescaleCard(c::AbstractDict)
    method::String = c["method"]
    rescaler::Rescaler = RESCALERS[method]
    by::Vector{String} = get(c, "by", String[])
    columns::Vector{String} = c["columns"]
    inverse_columns::Dict{String, String} = get(c, "inverse_columns") do
        return Dict(zip(columns, columns))
    end
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "rescaled")
    return RescaleCard(
        rescaler,
        by,
        columns,
        inverse_columns,
        partition,
        suffix
    )
end

## SQLCard interface

invertible(::RescaleCard) = true

sorting_vars(::RescaleCard) = String[]
grouping_vars(rc::RescaleCard) = rc.by
input_vars(rc::RescaleCard) = rc.columns
target_vars(::RescaleCard) = String[]
weight_var(::RescaleCard) = nothing
partition_var(rc::RescaleCard) = rc.partition
output_vars(rc::RescaleCard) = join_names.(rc.columns, rc.suffix)

function inverse_stats_vars(rc::RescaleCard)
    (; columns, inverse_columns) = rc
    cs = columns ∩ keys(inverse_columns)
    return cs, getindex.((inverse_columns,), cs)
end

function get_inverse_outputs(rc::RescaleCard)
    _, vars = inverse_stats_vars(rc)
    return vars
end

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
    (; by, columns, rescaler) = rc
    (; stats) = rescaler
    tbl = if isempty(stats)
        SimpleTable()
    else
        pair_wise_group_by(repository, source, by, columns, stats...; schema, rc.partition)
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
        invert = false
    )

    (; by, columns, inverse_columns, rescaler, suffix) = rc
    (; stats, transform, invtransform) = rescaler

    rescaled = if invert
        cs, cis = inverse_stats_vars(rc)
        @. cis => invtransform(cs, join_names(cis, suffix))
    else
        @. join_names(columns, suffix) => transform(columns)
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

function deevaluate(
        repository::Repository,
        rc::RescaleCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    return evaluate(repository, rc, state, source => destination; schema, invert = true)
end

## UI representation

function CardWidget(::Type{RescaleCard})

    options = collect(keys(RESCALERS))
    need_group = [k for (k, v) in pairs(RESCALERS) if !isempty(v.stats)]

    fields = [
        Widget("method"; options),
        Widget("by", visible = Dict("method" => need_group), required = false),
        Widget("columns"),
        Widget("partition", required = false),
        Widget("suffix", value = "rescaled"),
    ]

    return CardWidget(;
        type = "rescale",
        output = OutputSpec("columns", "suffix"),
        fields
    )
end
