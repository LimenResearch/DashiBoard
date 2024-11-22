struct RescaleCard <: AbstractCard
    method::String
    by::Vector{String}
    columns::Vector{String}
    suffix::String
end

inputs(r::RescaleCard) = union(r.by, r.columns)

outputs(r::RescaleCard) = r.columns .* '_' .* r.suffix

function rescaler(method, x)
    method == "zscore" && return Fun.:/(Fun.:-(x, Agg.mean(x)), Agg.stddev_pop(x))
    method == "maxabs" && return Fun.:/(x, Agg.max(Fun.abs(x)))
    method == "minmax" && return Fun.:/(Fun.:-(x, Agg.min(x)), Fun.:-(Agg.max(x), Agg.min(x)))
    method == "log" && return Fun.ln(x)
    method == "logistic" && return Fun.:/(1, Fun.:+(1, Fun.exp(Fun.:-(x))))
    throw(ArgumentError("method $method is not supported"))
end

function evaluate(
        r::RescaleCard,
        repo::Repository,
        (source, target)::Pair{<:AbstractString, <:AbstractString}
    )

    catalog = get_catalog(repo)
    select = colnames(catalog, source)
    selection = @. select => Get(select)

    rescaled = (Symbol(col, '_', r.suffix) => rescaler(r.method, Get(col)) for col in r.columns)

    query = From(source) |>
        Partition(by = Get.(r.by)) |>
        Select(selection..., rescaled...)

    sql = string(
        "CREATE OR REPLACE TABLE ",
        render(catalog, convert(SQLClause, target)),
        " AS\n",
        render(catalog, query)
    )

    DBInterface.execute(
        Returns(nothing),
        repo,
        sql,
    )
end

function RescaleCard(d::AbstractDict)
    method, by, columns, suffix = d["method"], d["by"], d["columns"], d["suffix"]
    return RescaleCard(method, by, columns, suffix)
end
