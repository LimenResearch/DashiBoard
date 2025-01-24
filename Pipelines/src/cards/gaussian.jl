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
    method::String = "identity"
    column::String
    means::Int
    max::Float64
    coef::Float64 = 0.5
    suffix::String = "gaussian"
    function GaussianEncodingCard(
            method::AbstractString,
            column::AbstractString,
            means::Integer,
            max::Real,
            coef::Real,
            suffix::AbstractString,
        )
        if !haskey(GAUSSIAN_METHODS, method)
            valid_methods = join(keys(GAUSSIAN_METHODS), ", ")
            throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods."))
        end
        means < 2 && throw(ArgumentError("`means` must be at least `2`. Provided value: `$means`."))
        new(method, column, means, max, coef, suffix)
    end
end

inputs(g::GaussianEncodingCard) = stringset(g.column)
outputs(g::GaussianEncodingCard) = stringset(string.(g.column, '_', g.suffix, '_', 1:g.means))

# TODO: might be periodic and first and last gaussian are the same?
function train(repo::Repository, g::GaussianEncodingCard, source::AbstractString; schema = nothing)
    μs = range(0, stop = 1, length = g.means)
    σ = step(μs) * g.coef
    params = Dict("σ" => [σ], "d" => [g.max])
    for (i, μ) in enumerate(μs)
        params["μ_$i"] = [μ]
    end
    return SimpleTable(params)
end

function evaluate(
        repo::Repository,
        g::GaussianEncodingCard,
        params_tbl::SimpleTable,
        (source, target)::Pair;
        schema = nothing
    )

    col = string(uuid4())
    converted = map(1:g.means) do i
        k = string(g.column, '_', g.suffix, '_', i)
        v = gaussian_transform(Get(col), Get(string("μ", '_', i)), Get.σ, Get.d)
        return k => v
    end

    preprocess = GAUSSIAN_METHODS[g.method]
    source_columns = colnames(repo, source; schema)
    target_columns = union(source_columns, first.(converted))
    return with_table(repo, params_tbl; schema) do tbl_name
        query = From(source) |>
            Define(col => preprocess(Get(g.column))) |>
            Join(From(tbl_name), on = true) |>
            Define(converted...) |>
            Select(Get.(target_columns)...)
        replace_table(repo, query, target; schema)
    end
end

function gaussian_transform(x, μ, σ, d)
    c = sqrt(2π)
    ω = @. ((x / d) - μ) / σ
    return @. exp(-ω * ω / 2) / (c * σ)
end

const GAUSSIAN_METHODS = OrderedDict(
    "identity" => identity,
    "dayofyear" => Fun.dayofyear,
    "hour" => Fun.hour
)

function CardWidget(
        ::Type{GaussianEncodingCard};
        means = (min = 2, step = 1, max = nothing),
        max = (min = 0, step = nothing, max = nothing),
        coef = (min = 0, step = nothing, max = nothing),
    )

    options = collect(keys(GAUSSIAN_METHODS))

    fields = [
        Widget("method"; options),
        Widget("column"),
        Widget("means"; means.min, means.step, means.max),
        Widget("max"; max.min, max.step, max.max),
        Widget("coef"; coef.min, coef.step, coef.max),
        Widget("suffix", value = "gaussian"),
    ]

    return CardWidget(;
        type = "gaussian_encoding",
        label = "Gaussian Encoding",
        output = OutputSpec("output"),
        fields
    )
end
