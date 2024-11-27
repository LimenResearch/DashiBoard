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
struct RescaleCard <: AbstractCard
    method::String
    by::Vector{String}
    columns::Vector{String}
    suffix::String
end

inputs(r::RescaleCard) = union(r.by, r.columns)

outputs(r::RescaleCard) = r.columns .* '_' .* r.suffix

function rescaler(r::RescaleCard, x::SQLNode)
    method = r.method

    method == "zscore" && return Fun.:/(Fun.:-(x, Agg.mean(x)), Agg.stddev_pop(x))
    method == "maxabs" && return Fun.:/(x, Agg.max(Fun.abs(x)))
    method == "minmax" && return Fun.:/(Fun.:-(x, Agg.min(x)), Fun.:-(Agg.max(x), Agg.min(x)))
    method == "log" && return Fun.ln(x)
    method == "logistic" && return Fun.:/(1, Fun.:+(1, Fun.exp(Fun.:-(x))))

    throw(ArgumentError("method $method is not supported"))
end

const NEEDS_GROUPING = Dict{String, Bool}(
    "zscore" => true,
    "maxabs" => true,
    "minmax" => true,
    "log" => false,
    "logistic" => false,
)

partition(r::RescaleCard) = NEEDS_GROUPING[r.method] ? Partition(by = Get.(r.by)) : identity

function evaluate(
        r::RescaleCard,
        repo::Repository,
        (source, target)::Pair{<:AbstractString, <:AbstractString}
    )

    rescaled = (Symbol(col, '_', r.suffix) => rescaler(r, Get(col)) for col in r.columns)

    query = From(source) |> partition(r) |> Define(rescaled...)

    replace_table(repo, target, query)
end

function RescaleCard(d::AbstractDict)
    method, by, columns, suffix = d["method"], d["by"], d["columns"], d["suffix"]
    return RescaleCard(method, by, columns, suffix)
end
