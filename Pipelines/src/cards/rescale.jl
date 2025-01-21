"""
    struct RescaleCard <: AbstractCard
        method::String
        by::Vector{String} = String[]
        columns::Vector{String}
        suffix::String = "rescaled"
    end

Card to rescale of one or more columns according to a given `method`.
The supported methods are
- `zscore`,
- `maxabs`,
- `minmax`,
- `log`,
- `logistic`.

The resulting rescaled variable is added to the table under the name
`"\$(originalname)_\$(suffix)"`. 
"""
@kwdef struct RescaleCard <: AbstractCard
    method::String
    by::Vector{String} = String[]
    columns::Vector{String}
    partition::Union{String, Nothing} = nothing
    suffix::String = "rescaled"
end

function inputs(r::RescaleCard)
    i = Set{String}()
    union!(i, r.by)
    union!(i, r.columns)
    isnothing(r.partition) || push!(i, r.partition)
    return i
end

outputs(r::RescaleCard) = Set(string.(r.columns, '_', r.suffix))

GetTransform(col, suffix) = Get(string(col, '_', suffix))

GetStats(name) = Get(name, over = Get.stats)

function GetStats(col, st)
    name = string(col, '_', st)
    return GetStats(name)
end

function zscore_transform(col)
    x = Get(col)
    μ = GetStats(col, "mean")
    σ = GetStats(col, "std")
    return @. (x - μ) / σ
end

function zscore_invtransform(col, suffix)
    y = GetTransform(col, suffix)
    μ = GetStats(col, "mean")
    σ = GetStats(col, "std")
    return @. μ + σ * y
end

function maxabs_transform(col)
    x = Get(col)
    m = GetStats(col, "maxabs")
    return @. x / m
end

function maxabs_invtransform(col, suffix)
    y = GetTransform(col, suffix)
    m = GetStats(col, "maxabs")
    return @. m * y
end

function minmax_transform(col)
    x = Get(col)
    x₀, x₁ = GetStats(col, "min"), GetStats(col, "max")
    return @. (x - x₀) / (x₁ - x₀)
end

function minmax_invtransform(col, suffix)
    y = GetTransform(col, suffix)
    x₀, x₁ = GetStats(col, "min"), GetStats(col, "max")
    return @. x₀ + (x₁ - x₀) * y
end

ln(x) = log(x) # for consistency with SQL

function log_transform(col)
    x = Get(col)
    return @. ln(x)
end

function log_invtransform(col, suffix)
    y = GetTransform(col, suffix)
    return @. exp(y)
end

function logistic_transform(col)
    x = Get(col)
    return @. 1 / (1 + exp(-x))
end

function logistic_invtransform(col)
    y = GetTransform(col, suffix)
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
    key = getindex.(Get, by)
    val = [string(col, '_', name) => f(Get(col)) for col in cols for (name, f) in fs]
    query = From(source) |> select |> Group(by = key) |> Select(key..., val...) |> Order(by = key)
    DBInterface.execute(fromtable, repo, query; schema)
end

function train(repo::Repository, r::RescaleCard, source::AbstractString; schema = nothing)
    (; by, columns, method) = r
    (; stats) = RESCALERS[method]
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

    (; by, columns, method, suffix) = r
    (; stats, transform, invtransform) = RESCALERS[method]

    available_columns = colnames(repo, source; schema)
    rescaled = if invert
        [c => invtransform(c, suffix) for c in columns if string(c, '_', suffix) in available_columns]
    else
        [string(c, '_', suffix) => transform(c) for c in columns if c in available_columns]
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
        SelectWidget("method"; options),
        SelectWidget("by", visible = Dict("method" => need_group)),
        SelectWidget("columns"),
        SelectWidget("partition"),
        SuffixWidget(value = "rescaled"),
    ]

    return CardWidget(;
        type = "rescale",
        label = "Rescale",
        output = OutputSpec("columns", "suffix"),
        fields
    )
end
