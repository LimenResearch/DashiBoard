const TEMPORAL_PREPROCESSING = OrderedDict(
    "identity" => identity,
    "dayofyear" => Fun.dayofyear,
    "hour" => Fun.hour
)

"""
    struct GaussianEncodingCard <: AbstractCard

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
  - `"hour"`: Assumes the column is a time or timestamp.

Methods:
- Defined in the `TEMPORAL_PREPROCESSING` dictionary:
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
struct GaussianEncodingCard <: AbstractCard
    column::String
    processed_column::SQLNode
    n_modes::Int
    max::Float64
    lambda::Float64
    suffix::String
end

function GaussianEncodingCard(c::Config)
    column::String = c.column
    method::String = get(c, :method, "identity")
    if !haskey(TEMPORAL_PREPROCESSING, method)
        valid_methods = join(keys(TEMPORAL_PREPROCESSING), ", ")
        throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods."))
    end
    processed_column::SQLNode = TEMPORAL_PREPROCESSING[method](Get(column))
    n_modes::Int = c.n_modes
    n_modes < 2 && throw(ArgumentError("`n_modes` must be at least `2`. Provided value: `$n_modes`."))
    max::Float64 = c.max
    lambda::Float64 = get(c, :lambda, 0.5)
    suffix::String = get(c, :suffix, "gaussian")
    return GaussianEncodingCard(column, processed_column, n_modes, max, lambda, suffix)
end

invertible(::GaussianEncodingCard) = false

inputs(g::GaussianEncodingCard) = stringset(g.column)
outputs(g::GaussianEncodingCard) = stringset(join_names.(g.column, g.suffix, 1:g.n_modes))

# TODO: might be periodic and first and last gaussian are the same?
function train(repo::Repository, g::GaussianEncodingCard, source::AbstractString; schema = nothing)
    μs = range(0, stop = 1, length = g.n_modes)
    σ = step(μs) * g.lambda
    params = Dict("σ" => [σ], "d" => [g.max])
    for (i, μ) in enumerate(μs)
        params["μ_$i"] = [μ]
    end
    tbl = SimpleTable(params)
    return CardState(
        content = jldserialize(tbl)
    )
end

function gaussian_transform(x, μ, σ, d)
    c = sqrt(2π)
    ω = @. ((x / d) - μ) / σ
    return @. exp(-ω * ω / 2) / c
end

function evaluate(
        repo::Repository,
        g::GaussianEncodingCard,
        state::CardState,
        (source, target)::Pair;
        schema = nothing
    )

    params_tbl = jlddeserialize(state.content)

    source_columns = colnames(repo, source; schema)
    col = new_name("transformed", source_columns)
    converted = map(1:g.n_modes) do i
        k = join_names(g.column, g.suffix, i)
        v = gaussian_transform(Get(col), Get(join_names("μ", i)), Get.σ, Get.d)
        return k => v
    end
    target_columns = union(source_columns, first.(converted))

    return with_table(repo, params_tbl; schema) do tbl_name
        query = From(source) |>
            Define(col => g.processed_column) |>
            Join(From(tbl_name), on = true) |>
            Define(converted...) |>
            Select(Get.(target_columns)...)
        replace_table(repo, query, target; schema)
    end
end

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
