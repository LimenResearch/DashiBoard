"""
    struct GaussianEncodingCard <: AbstractCard

Defines a card for applying Gaussian transformations to a specified column.

Fields:
- `column::String`: Name of the column to transform.
- `means::Int`: Number of Gaussian distributions to generate.
- `max::Float64`: Maximum value used for normalization (denominator).
- `coef::Float64`: Coefficient for scaling the standard deviation.
- `suffix::String`: Suffix added to the output column names.
- `method::String`: Preprocessing method applied to the column (e.g., `"identity"`, `"dayofyear"`, `"hour"`).

Notes:
- The `method` field determines the preprocessing applied to the column.
- No automatic selection based on column type. The user must ensure compatibility:
  - `"identity"`: Assumes the column is numeric.
  - `"dayofyear"`: Assumes the column is a date or timestamp.
  - `"hour"`: Assumes the column is a time or timestamp.

Methods:
- Defined in the `GAUSSIAN_METHODS` dictionary:
  - `"identity"`: No transformation.
  - `"dayofyear"`: Applies the SQL `dayofyear` function.
  - `"hour"`: Applies the SQL `hour` function.

Train:
- Returns: SimpleTable (Dict{String, AbstractVector}) with Gaussian parameters:
  - `σ`: Standard deviation for Gaussian transformations.
  - `d`: Normalization value.
  - `μ_1, μ_2, ..., μ_n`: Gaussian means.

Evaluate:
- Steps:
  1. Preprocesses the column using the specified method.
  2. Temporarily registers the Gaussian parameters (`params_tbl`) using `with_table`.
  3. Joins the source table with the params table via a CROSS JOIN.
  4. Computes Gaussian-transformed columns.
  5. Selects only the required columns (original and transformed).
  6. Replaces the target table with the final results.
"""
@kwdef struct GaussianEncodingCard <: AbstractCard
    column::String
    means::Int
    max::Float64
    coef::Float64  = 0.5
    suffix::String = "gaussian"
    method::String = "identity"
    function GaussianEncodingCard(column, means, max, coef, suffix, method)
        if !haskey(GAUSSIAN_METHODS, method)
            valid_methods = join(keys(GAUSSIAN_METHODS), ", ")
            throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods"))
        end
        means <= 1 && throw(ArgumentError("`means` must be greater than 1. Provided value: $means"))
        new(column, means, max, coef, suffix, method)
    end
end

inputs(g::GaussianEncodingCard) = Set{String}([g.column])
sorted_outputs(g::GaussianEncodingCard) = [string(g.column, "_", g.suffix, "_", i) for i in 1:g.means]
outputs(g::GaussianEncodingCard) = Set{String}(sorted_outputs(g))

function gaussian_train(g::GaussianEncodingCard)
    μs = range(0, stop=1, length=g.means)
    σ = round(step(μs) * g.coef, digits=4)
    params = Dict("σ" => [σ], "d" => [g.max])
    for (i, μ) in enumerate(μs)
        params["μ_$i"] = [μ]
    end
    return SimpleTable(params)
end

train(repo::Repository, g::GaussianEncodingCard, source::AbstractString; schema = nothing) = gaussian_train(g::GaussianEncodingCard)

function evaluate(repo::Repository, g::GaussianEncodingCard, params_tbl::SimpleTable, (source, target)::Pair; schema = nothing)
    preprocess = get(GAUSSIAN_METHODS, g.method, nothing)
    if isnothing(preprocess)
        throw(ArgumentError("Method $(g.method) is not supported. Valid methods: $(join(keys(GAUSSIAN_METHODS), ", "))"))
    end
    transformed_id = string(uuid4())
    converted = [
        string(g.column, "_", g.suffix, "_", i) => gaussian_transform(Get(transformed_id), Get(Symbol("μ_$i")), Get(:σ), Get(:d))
        for i in 1:g.means
    ]
    with_table(repo, params_tbl; schema) do tbl_name
        join_query = From(source) |>
            Define(transformed_id => preprocess(Get(g.column))) |>
            Join(From(tbl_name), on = true) |>
            Define(converted...)
        source_columns = colnames(repo, source; schema)
        select_query = join_query |>
            Select(Get.(Symbol.(union(source_columns, outputs(g))))...)
        replace_table(repo, select_query, target; schema)
    end
end

function gaussian_transform(x, μ, σ, d)
    c = sqrt(2π)
    ω = @. ((x / d) - μ) / σ
    return @. exp(-ω * ω / 2) / (c * σ)
end

const GAUSSIAN_METHODS = Dict(
    "identity" => identity,
    "dayofyear" => Fun.dayofyear,
    "hour" => Fun.hour
)
