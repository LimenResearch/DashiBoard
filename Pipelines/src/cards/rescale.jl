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
    struct RescaleCard <: AbstractCard
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
struct RescaleCard <: AbstractCard
    rescaler::Rescaler
    by::Vector{String}
    columns::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
end

function RescaleCard(c::Config)
    method::String = c.method
    rescaler::Rescaler = RESCALERS[method]
    by::Vector{String} = get(c, :by, String[])
    columns::Vector{String} = c.columns
    partition::Union{String, Nothing} = get(c, :partition, nothing)
    suffix::String = get(c, :suffix, "rescaled")
    return RescaleCard(
        rescaler,
        by,
        columns,
        partition,
        suffix
    )
end

invertible(::RescaleCard) = true

inputs(r::RescaleCard) = stringset(r.by, r.columns, r.partition)

outputs(r::RescaleCard) = stringset(join_names.(r.columns, r.suffix))

function pair_wise_group_by(
        repo::Repository,
        source::AbstractString,
        by::AbstractVector,
        cols::AbstractVector,
        fs...;
        partition::Union{AbstractString, Nothing} = nothing,
        schema = nothing,
    )

    select = filter_partition(partition)
    key = Get.(by)
    val = [join_names(col, name) => f(Get(col)) for col in cols for (name, f) in fs]
    query = From(source) |> select |> Group(by = key) |> Select(key..., val...) |> Order(by = key)
    DBInterface.execute(fromtable, repo, query; schema)
end

function train(repo::Repository, r::RescaleCard, source::AbstractString; schema = nothing)
    (; by, columns, rescaler) = r
    (; stats) = rescaler
    return if isempty(stats)
        SimpleTable()
    else
        pair_wise_group_by(repo, source, by, columns, stats...; schema, r.partition)
    end
end

function evaluate(
        repo::Repository,
        r::RescaleCard,
        stats_tbl::SimpleTable,
        (source, dest)::Pair;
        schema = nothing,
        invert = false
    )

    (; by, columns, rescaler, suffix) = r
    (; stats, transform, invtransform) = rescaler

    available_columns = colnames(repo, source; schema)
    iter = ((c, join_names(c, suffix)) for c in columns)

    rescaled = if invert
        [c => invtransform(c, c′) for (c, c′) in iter if c′ in available_columns]
    else
        [c′ => transform(c) for (c, c′) in iter if c in available_columns]
    end

    if isempty(stats)
        query = From(source) |> Define(rescaled...)
        replace_table(repo, query, dest; schema)
    else
        with_table(repo, stats_tbl; schema) do tbl_name
            eqs = (.==).(Get.(by), GetStats.(by))
            query = From(source) |>
                LeftJoin("stats" => From(tbl_name); on = Fun.and(eqs...)) |>
                Define(rescaled...)
            replace_table(repo, query, dest; schema)
        end
    end
end

function deevaluate(
        repo::Repository,
        r::RescaleCard,
        stats_tbl::SimpleTable,
        (source, dest)::Pair;
        schema = nothing
    )

    evaluate(repo, r, stats_tbl, source => dest; schema, invert = true)
end

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
        label = "Rescale",
        output = OutputSpec("columns", "suffix"),
        fields
    )
end
