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
    return Fun.:/(Fun.:-(x, μ), σ)
end

maxabs_transform(col) = Fun.:/(Get[col], Get.stats[string(col, '_', "maxabs")])

function minmax_transform(col)
    x = Get[col]
    x₀, x₁ = Get.stats[string(col, '_', "min")], Get.stats[string(col, '_', "max")]
    return Fun.:/(Fun.:-(x, x₀), Fun.:-(x₁, x₀))
end

log_transform(col) = Fun.ln(Get[col])
logistic_transform(col) = Fun.:/(1, Fun.:+(1, Fun.exp(Fun.:-(Get[col]))))

struct Rescaler
    stats::Vector{Pair}
    transform::Base.Callable
end

const RESCALERS = Dict{String, Rescaler}(
    "zscore" => Rescaler(Pair["mean" => Agg.mean, "std" => Agg.stddev_pop], zscore_transform),
    "maxabs" => Rescaler(Pair["maxabs" => Agg.max ∘ Fun.abs], maxabs_transform),
    "minmax" => Rescaler(Pair["max" => Agg.max, "min" => Agg.min], minmax_transform),
    "log" => Rescaler(Pair[], log_transform),
    "logistic" => Rescaler(Pair[], logistic_transform)
)

function pair_wise_group_by(
        repo::Repository,
        source::AbstractString,
        by::AbstractVector,
        cols::AbstractVector,
        fs...
    )

    key = getindex.(Get, by)
    val = [string(col, '_', name) => f(Get[col]) for col in cols for (name, f) in fs]
    query = From(source) |> Group(by = key) |> Select(key..., val...)
    DBInterface.execute(fromtable, repo, query)
end

function plan(r::RescaleCard, repo::Repository, source::AbstractString)
    (; by, columns, method) = r
    (; stats) = RESCALERS[method]
    return isempty(stats) ? SimpleTable() : pair_wise_group_by(repo, source, by, columns, stats...)
end

function evaluate(r::RescaleCard, repo::Repository, (source, target)::StringPair)
    stats_tbl = plan(r, repo, source)
    return evaluate(r, repo, source => target, stats_tbl)
end

function evaluate(r::RescaleCard, repo::Repository, (source, target)::StringPair, stats_tbl::SimpleTable)
    (; by, columns, method, suffix) = r
    (; stats, transform) = RESCALERS[method]
    rescaled = (string(col, '_', suffix) => transform(col) for col in columns)
    if isempty(stats)
        query = From(source) |> Define(rescaled...)
        replace_table(repo, target, query)
    else
        with_table(repo, stats_tbl) do tbl_name
            eqs = [Fun("=", Get[col], Get.stats[col]) for col in by]
            query = From(source) |>
                Join("stats" => From(tbl_name); on = Fun.and(eqs...)) |>
                Define(rescaled...)
            replace_table(repo, target, query)
        end
    end
end

function RescaleCard(d::AbstractDict)
    method, by, columns, suffix = d["method"], d["by"], d["columns"], d["suffix"]
    return RescaleCard(method, by, columns, suffix)
end
