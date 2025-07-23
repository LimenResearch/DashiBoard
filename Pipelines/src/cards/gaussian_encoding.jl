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
- `type::String`: Card type, i.e., `"gaussian_encoding"`.
- `label::String`: Label to represent the card in a UI.
- `input::String`: Name of the column to transform.
- `processed_input::Union{FunClosure, Nothing}`: Processed column using a given method (see below).
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
    type::String
    label::String
    method::String
    input::String
    processed_input::SQLNode
    n_modes::Int
    max::Float64
    lambda::Float64
    suffix::String
end

const GAUSSIAN_ENCODING_CARD_CONFIG =
    CardConfig{GaussianEncodingCard}(parse_toml_config("config", "gaussian_encoding"))

function get_metadata(gec::GaussianEncodingCard)
    return StringDict(
        "type" => gec.type,
        "label" => gec.label,
        "method" => gec.method,
        "input" => gec.input,
        "n_modes" => gec.n_modes,
        "max" => gec.max,
        "lambda" => gec.lambda,
        "suffix" => gec.suffix,
    )
end

function GaussianEncodingCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    method::String = get(c, "method", "identity")
    input::String = c["input"]
    if !haskey(TEMPORAL_PREPROCESSING, method)
        valid_methods = join(keys(TEMPORAL_PREPROCESSING), ", ")
        throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods."))
    end
    processed_input::SQLNode = TEMPORAL_PREPROCESSING[method](Get(input))
    n_modes::Int = c["n_modes"]
    if n_modes ≤ 0
        throw(ArgumentError("`n_modes` must be greater than `0`. Provided value: `$n_modes`."))
    end
    max::Float64 = get(c, "max", TEMPORAL_MAX[method])
    lambda::Float64 = get(c, "lambda", 0.5)
    suffix::String = get(c, "suffix", "gaussian")
    return GaussianEncodingCard(type, label, method, input, processed_input, n_modes, max, lambda, suffix)
end

## SQLCard interface

sorting_vars(::GaussianEncodingCard) = String[]
grouping_vars(::GaussianEncodingCard) = String[]
input_vars(gec::GaussianEncodingCard) = [gec.input]
target_vars(::GaussianEncodingCard) = String[]
weight_var(::GaussianEncodingCard) = nothing
partition_var(::GaussianEncodingCard) = nothing
output_vars(gec::GaussianEncodingCard) = join_names.(gec.input, gec.suffix, 1:gec.n_modes)

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
        (source, destination)::Pair,
        id_var::AbstractString;
        schema = nothing
    )

    params_tbl = jlddeserialize(state.content)

    converted = map(1:gec.n_modes) do i
        k = join_names(gec.input, gec.suffix, i)
        v = gaussian_transform(Get.transformed, Get(join_names("μ", i)), Get.σ, Get.d)
        return k => v
    end
    selection = vcat([id_var => Get(id_var)], converted)

    with_table(repository, params_tbl; schema) do tbl_name
        query = From(source) |>
            Partition() |>
            Select(id_var => Agg.row_number(), "transformed" => gec.processed_input) |>
            Join(From(tbl_name), on = true) |>
            Select(args = selection)
        replace_table(repository, query, destination; schema)
    end
    return
end

## UI representation

function CardWidget(config::CardConfig{GaussianEncodingCard}, options::AbstractDict)
    methods = collect(keys(TEMPORAL_PREPROCESSING))

    n_modes_options = get(options, "n_modes", StringDict("min" => 1, "step" => 1))
    max_options = get(options, "max", StringDict("min" => 0))
    lambda_options = get(options, "lambda", StringDict("min" => 0))

    fields = [
        Widget("method"; options = methods),
        Widget("input"),
        Widget(config, "n_modes", n_modes_options),
        Widget(config, "max", max_options),
        Widget(config, "lambda", lambda_options),
        Widget("suffix", value = "gaussian"),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("input", "suffix", "n_modes"))
end
