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
- defined in GAUSSIAN_METHODS Dictionary.
- Keys:
- `"identity"`: No transformation.
- `"dayofyear"`: Applies the SQL `dayofyear` function.
- `"hour"`: Applies the SQL `hour` function.

Values:
- Functions taking a column name and returning the corresponding SQL transformation.

Train:
- Returns: SimpleTable (Dict{String, AbstractVector}) with Gaussian parameters:
- `σ`: Standard deviation for the Gaussian transformations.
- `d`: Normalization value.
- `μ_1, μ_2, ..., μ_n`: Gaussian means.

Evaluate:
-Steps:
1. Preprocesses the column using the specified method (e.g., `"dayofyear"`, `"hour"`, `"identity"`).
2. Temporarily registers the Gaussian parameters (`params_tbl`) using `with_table`.
3. Joins the source table (with preprocessing applied) with the params table via a CROSS JOIN.
4. Computes Gaussian-transformed columns (`gaussian_1`, `gaussian_2`, ...).
5. Selects only the required columns (original and transformed), excluding intermediate values.
6. Replaces the target table with the final results.
"""
@kwdef struct GaussianEncodingCard <: AbstractCard
    column::String
    means::Int
    max::Float64
    coef::Float64  = 0.5
    suffix::String = "gaussian"
    method::String = "identity"  # Default preprocessing method
end

inputs(g::GaussianEncodingCard) = Set{String}([g.column])
outputs(g::GaussianEncodingCard) = OrderedSet{String}([string(g.column, "_", g.suffix, "_", i) for i in 1:g.means])

"""
gaussian_train(repo::Repository, g::GaussianEncodingCard; schema=nothing) -> SimpleTable

Generates a SimpleTable containing:
- `σ`: Standard deviation for the Gaussian transformations.
- `d`: Normalization value.
- `μ_1, μ_2, ..., μ_n`: Gaussian means.

Returns:
- A SimpleTable (Dict{String, AbstractVector}) with Gaussian parameters.
"""
function gaussian_train(g::GaussianEncodingCard)
    μs = range(0, stop=1, length=g.means)  # Means normalized between 0 and 1
    σ = round(step(μs) * g.coef, digits=4)
    params = Dict("σ" => [σ], "d" => [g.max])
    for (i, μ) in enumerate(μs)
        params["μ_$i"] = [μ]
    end
    return SimpleTable(params)
end


train(repo::Repository, g::GaussianEncodingCard, source::AbstractString; schema = nothing) = gaussian_train(g::GaussianEncodingCard)

function evaluate(
    repo::Repository, g::GaussianEncodingCard, params_tbl::SimpleTable, (source, target)::Pair; schema = nothing
)
    preprocess = get(GAUSSIAN_METHODS, g.method, nothing)
    if isnothing(preprocess)
        throw(ArgumentError("Method $(g.method) is not supported for GaussianEncodingCard"))
    end

    transformed_id = string(uuid4())

    converted = [
        string(g.column, "_", g.suffix, "_", i) => gaussian_transform(
            Get(transformed_id), Get(Symbol("μ_$i")), Get(:σ), Get(:d)
        ) for i in 1:g.means
    ]
    
    with_table(repo, params_tbl; schema) do tbl_name
        join_query = From(source) |>
            Define(transformed_id => preprocess(Get(g.column))) |>
            Join(From(tbl_name), on = true) |>  # CROSS JOIN with params table
            Define(converted...) |>
            transform_query
        source_columns = colnames(repo, source; schema)
        select_query = join_query |>
            Select(Get.(Symbol.(union(source_columns, outputs(g))))...)
        replace_table(repo, select_query, target; schema)
    end
end

"""
gaussian_transform(x, μ, σ, d) -> Float64

Computes the Gaussian transformation:
    1/2(sqrt(2πσ^2)) * exp(-((x / d) - μ)^2)/2σ^2)

Args:
- `x`: Input value to transform.
- `μ`: Gaussian mean.
- `σ`: Standard deviation.
- `d`: Normalization denominator.

Returns:
- Transformed value as Float64.
"""
function gaussian_transform(x, μ, σ, d)
    c = sqrt(2π)
    ω = @. ( (x  / d) - μ ) / σ
    return @. exp( - ω * ω / 2 ) / ( c * σ )
end


const GAUSSIAN_METHODS = Dict(
    "identity" => identity,  # No transformation
    "dayofyear" => Fun.dayofyear,  # SQL dayofyear function
    "hour" => Fun.hour  # SQL hour function
)