"""
    struct RescaleCard <: AbstractCard
        method::String
        by::Vector{String}
        columns::Vector{String}
        suffix::String
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
    suffix::String = "rescaled"
end

inputs(r::RescaleCard) = union(r.by, r.columns)

outputs(r::RescaleCard) = string.(r.columns, '_', r.suffix)

function zscore_transform(col)
    x = Get[col]
    μ = Get.stats[string(col, '_', "mean")]
    σ = Get.stats[string(col, '_', "std")]
    return @. (x - μ) / σ
end

function zscore_invtransform(col, suffix)
    y = Get[string(col, '_', suffix)]
    μ = Get.stats[string(col, '_', "mean")]
    σ = Get.stats[string(col, '_', "std")]
    return @. μ + σ * y
end

function maxabs_transform(col)
    x = Get[col]
    m = Get.stats[string(col, '_', "maxabs")]
    return @. x / m
end

function maxabs_invtransform(col, suffix)
    y = Get[string(col, '_', suffix)]
    m = Get.stats[string(col, '_', "maxabs")]
    return @. m * y
end

function minmax_transform(col)
    x = Get[col]
    x₀, x₁ = Get.stats[string(col, '_', "min")], Get.stats[string(col, '_', "max")]
    return @. (x - x₀) / (x₁ - x₀)
end

function minmax_invtransform(col, suffix)
    y = Get[string(col, '_', suffix)]
    x₀, x₁ = Get.stats[string(col, '_', "min")], Get.stats[string(col, '_', "max")]
    return @. x₀ + (x₁ - x₀) * y
end

ln(x) = log(x) # for consistency with SQL

function log_transform(col)
    x = Get[col]
    return @. ln(x)
end

function log_invtransform(col, suffix)
    y = Get[string(col, '_', suffix)]
    return @. exp(y)
end

function logistic_transform(col)
    x = Get[col]
    return @. 1 / (1 + exp(-x))
end

function logistic_invtransform(col)
    y = Get[string(col, '_', suffix)]
    return @. ln(y / (1 - y))
end

struct Rescaler
    stats::Vector{Pair}
    transform::Base.Callable
    invtransform::Union{Base.Callable, Nothing}
end

const RESCALERS = Dict{String, Rescaler}(
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
        schema = nothing
    )

    key = getindex.(Get, by)
    val = [string(col, '_', name) => f(Get[col]) for col in cols for (name, f) in fs]
    query = From(source) |> Group(by = key) |> Select(key..., val...)
    DBInterface.execute(fromtable, repo, query; schema)
end

function plan(r::RescaleCard, repo::Repository, source::AbstractString; schema = nothing)
    (; by, columns, method) = r
    (; stats) = RESCALERS[method]
    return isempty(stats) ? SimpleTable() : pair_wise_group_by(repo, source, by, columns, stats...; schema)
end

function evaluate(r::RescaleCard, repo::Repository, (source, target)::StringPair; schema = nothing)
    stats_tbl = plan(r, repo, source; schema)
    return evaluate(r, repo, source => target, stats_tbl; schema)
end

function evaluate(r::RescaleCard, repo::Repository, (source, target)::StringPair, stats_tbl::SimpleTable; schema = nothing)
    (; by, columns, method, suffix) = r
    (; stats, transform) = RESCALERS[method]
    rescaled = (string(col, '_', suffix) => transform(col) for col in columns)
    if isempty(stats)
        query = From(source) |> Define(rescaled...)
        replace_table(repo, query, target; schema)
    else
        with_table(repo, stats_tbl; schema) do tbl_name
            eqs = [Fun("=", Get[col], Get.stats[col]) for col in by]
            query = From(source) |>
                LeftJoin("stats" => From(tbl_name); on = Fun.and(eqs...)) |>
                Define(rescaled...)
            replace_table(repo, query, target; schema)
        end
    end
end

function deevaluate(r::RescaleCard, repo::Repository, (source, target)::StringPair, stats_tbl::SimpleTable; schema = nothing)
    (; by, columns, method, suffix) = r
    (; stats, invtransform) = RESCALERS[method]
    rescaled = (col => invtransform(col, suffix) for col in columns)
    if isempty(stats)
        query = From(source) |> Define(rescaled...)
        replace_table(repo, query, target; schema)
    else
        with_table(repo, stats_tbl; schema) do tbl_name
            eqs = [Fun("=", Get[col], Get.stats[col]) for col in by]
            query = From(source) |>
                LeftJoin("stats" => From(tbl_name); on = Fun.and(eqs...)) |>
                Define(rescaled...)
            replace_table(repo, query, target; schema)
        end
    end
end

function RescaleCard(d::AbstractDict)
    method, by, columns, suffix = d["method"], d["by"], d["columns"], d["suffix"]
    return RescaleCard(method, by, columns, suffix)
end
