minuteofday(x) = @. hour(x) * 60 + minute(x)

minuteofhour(x) = @. minute(x)

const TEMPORAL_PREPROCESSING = OrderedDict(
    "identity" => identity,
    "dayofyear" => Fun.dayofyear,
    "hourofday" => Fun.hour,
    "minuteofday" => minuteofday,
    "minuteofhour" => minuteofhour,
)

const TEMPORAL_MAX = OrderedDict(
    "identity" => 1,
    "dayofyear" => 366,
    "hourofday" => 24,
    "minuteofday" => 1440,
    "minuteofhour" => 60,
)

"""
    struct GaussianEncodingCard <: Card

Defines a card for applying Gaussian transformations to a specified column.

Fields:
- `column::String`: Name of the column to transform.
- `processed_column::Union{FunClosure, Nothing}`: Processed column using a given method (see below).
- `n_modes::Int`: Number of Gaussian curves to generate.
- `max::Float64`: Maximum value used for normalization (denominator).
- `lambda::Float64`: Coefficient for scaling the standard deviation.
- `suffix::String`: Suffix added to the output column names.

Notes:
- The `method` field determines the preprocessing applied to the column.
- No automatic selection based on column type. The user must ensure compatibility:
  - `"identity"`: Assumes the column is numeric.
  - `"dayofyear"`: Assumes the column is a date or timestamp.
  - `"hourofday"`: Assumes the column is a time or timestamp.

Methods:
- Defined in the `TEMPORAL_PREPROCESSING` dictionary:
  - `"identity"`: No transformation.
  - `"dayofyear"`: Applies the SQL `dayofyear` function.
  - `"hourofday"`: Applies the SQL `hour` function.

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
struct GaussianEncodingCard <: SQLCard
    column::String
    processed_column::SQLNode
    n_modes::Int
    max::Float64
    lambda::Float64
    suffix::String
end

register_card("gaussian_encoding", GaussianEncodingCard)

function GaussianEncodingCard(c::AbstractDict)
    column::String = c["column"]
    method::String = get(c, "method", "identity")
    if !haskey(TEMPORAL_PREPROCESSING, method)
        valid_methods = join(keys(TEMPORAL_PREPROCESSING), ", ")
        throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods."))
    end
    processed_column::SQLNode = TEMPORAL_PREPROCESSING[method](Get(column))
    n_modes::Int = c["n_modes"]
    if n_modes ≤ 0
        throw(ArgumentError("`n_modes` must be greater than `0`. Provided value: `$n_modes`."))
    end
    max::Float64 = get(c, "max", TEMPORAL_MAX[method])
    lambda::Float64 = get(c, "lambda", 0.5)
    suffix::String = get(c, "suffix", "gaussian")
    return GaussianEncodingCard(column, processed_column, n_modes, max, lambda, suffix)
end

## SQLCard interface

sorting_vars(::GaussianEncodingCard) = String[]
grouping_vars(::GaussianEncodingCard) = String[]
input_vars(gec::GaussianEncodingCard) = [gec.column]
target_vars(::GaussianEncodingCard) = String[]
weight_var(::GaussianEncodingCard) = nothing
partition_var(::GaussianEncodingCard) = nothing
output_vars(gec::GaussianEncodingCard) = join_names.(gec.column, gec.suffix, 1:gec.n_modes)

function train(::Repository, gec::GaussianEncodingCard, source::AbstractString; schema = nothing)
    μs = range(start = 0, step = 1 / gec.n_modes, length = gec.n_modes)
    σ = step(μs) * gec.lambda
    params = Dict("σ" => [σ], "d" => [gec.max])
    for (i, μ) in enumerate(μs)
        params["μ_$i"] = [μ]
    end
    tbl = SimpleTable(params)
    return CardState(content = jldserialize(tbl))
end

function gaussian_transform(x, μ, σ, d)
    c = sqrt(2π)
    η = @. (x / d) - μ
    ω = @. abs(η - round(η)) / σ
    return @. exp(- ω * ω / 2) / c
end

function evaluate(
        repository::Repository,
        gec::GaussianEncodingCard,
        state::CardState,
        (source, target)::Pair;
        schema = nothing
    )

    params_tbl = jlddeserialize(state.content)

    source_columns = colnames(repository, source; schema)
    col = new_name("transformed", source_columns, get_outputs(gec))
    converted = map(1:gec.n_modes) do i
        k = join_names(gec.column, gec.suffix, i)
        v = gaussian_transform(Get(col), Get(join_names("μ", i)), Get.σ, Get.d)
        return k => v
    end
    target_columns = union(source_columns, first.(converted))

    return with_table(repository, params_tbl; schema) do tbl_name
        query = From(source) |>
            Define(col => gec.processed_column) |>
            Join(From(tbl_name), on = true) |>
            Define(converted...) |>
            Select(Get.(target_columns)...)
        replace_table(repository, query, target; schema)
    end
end

## UI representation

function CardWidget(
        ::Type{GaussianEncodingCard};
        n_modes = (min = 2, step = 1, max = nothing),
        max = (min = 0, step = nothing, max = nothing),
        lambda = (min = 0, step = nothing, max = nothing),
    )

    options = collect(keys(TEMPORAL_PREPROCESSING))

    fields = [
        Widget("method"; options),
        Widget("column"),
        Widget("n_modes"; n_modes.min, n_modes.step, n_modes.max),
        Widget("max"; max.min, max.step, max.max),
        Widget("lambda"; lambda.min, lambda.step, lambda.max),
        Widget("suffix", value = "gaussian"),
    ]

    return CardWidget(;
        type = "gaussian_encoding",
        label = "Gaussian Encoding",
        output = OutputSpec("column", "suffix", "n_modes"),
        fields
    )
end
