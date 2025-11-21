abstract type TemporalProcessingMethod end

struct IdentityMethod <: TemporalProcessingMethod
    max::Float64
end
IdentityMethod(c::AbstractDict) = IdentityMethod(Float64(get(c, "max", 1)))
(::IdentityMethod)(x::SQLNode) = x

struct DayOfYearMethod <: TemporalProcessingMethod
    max::Float64
end
DayOfYearMethod(c::AbstractDict) = DayOfYearMethod(Float64(get(c, "max", 366)))
(::DayOfYearMethod)(x::SQLNode) = Fun.dayofyear(x)

struct HourOfDayMethod <: TemporalProcessingMethod
    max::Float64
end
HourOfDayMethod(c::AbstractDict) = HourOfDayMethod(Float64(get(c, "max", 24)))
(::HourOfDayMethod)(x::SQLNode) = Fun.hour(x)

struct MinuteOfDayMethod <: TemporalProcessingMethod
    max::Float64
end
MinuteOfDayMethod(c::AbstractDict) = MinuteOfDayMethod(Float64(get(c, "max", 1440)))
(::MinuteOfDayMethod)(x::SQLNode) = @. hour(x) * 60 + minute(x)

struct MinuteOfHourMethod <: TemporalProcessingMethod
    max::Float64
end
MinuteOfHourMethod(c::AbstractDict) = MinuteOfHourMethod(Float64(get(c, "max", 60)))
(::MinuteOfHourMethod)(x::SQLNode) = @. minute(x)

struct DayOfWeekMethod <: TemporalProcessingMethod
    max::Float64
end
DayOfWeekMethod(c::AbstractDict) = DayOfWeekMethod(Float64(get(c, "max", 7)))
(::DayOfWeekMethod)(x::SQLNode) = Fun.dayofweek(x)

const TEMPORAL_PREPROCESSING_METHODS = OrderedDict{String, DataType}(
    "identity" => IdentityMethod,
    "dayofyear" => DayOfYearMethod,
    "hourofday" => HourOfDayMethod,
    "minuteofday" => MinuteOfDayMethod,
    "minuteofhour" => MinuteOfHourMethod,
    "dayofweek" => DayOfWeekMethod,
)

"""
    struct GaussianEncodingCard <: Card

Defines a card for applying Gaussian transformations to a specified column.

Fields:
- `type::String`: Card type, i.e., `"gaussian_encoding"`.
- `label::String`: Label to represent the card in a UI.
- `method::String`: Name of the processing method (see below).
- `temporal_preprocessor::TemporalProcessingMethod`: Tranformation to process a given column (see below).
- `input::String`: Name of the column to transform.
- `n_components::Int`: Number of Gaussian curves to generate.
- `lambda::Float64`: Coefficient for scaling the standard deviation.
- `suffix::String`: Suffix added to the output column names.

Notes:
- The `method` field determines the preprocessing applied to the column.
- No automatic selection based on column type. The user must ensure compatibility:
  - `"identity"`: Assumes the column is numeric.
  - `"dayofyear"`: Assumes the column is a date or timestamp.
  - `"hourofday"`: Assumes the column is a time or timestamp.

Methods:
- Defined in the `TEMPORAL_PREPROCESSING_METHODS` dictionary:
  - `"identity"`: No transformation.
  - `"dayofyear"`: Applies the SQL `dayofyear` function.
  - `"hourofday"`: Applies the SQL `hour` function.
  - `"minuteofhour"`: Computes the minute within the hour.
  - `"minuteofday"`: Computes the minute within the day.

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
    temporal_preprocessor::TemporalProcessingMethod
    input::String
    n_components::Int
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
        "method_options" => get_options(gec.temporal_preprocessor),
        "input" => gec.input,
        "n_components" => gec.n_components,
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
    if !haskey(TEMPORAL_PREPROCESSING_METHODS, method)
        valid_methods = join(keys(TEMPORAL_PREPROCESSING_METHODS), ", ")
        throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods."))
    end
    method_options::StringDict = extract_options(c, "method", method)
    temporal_preprocessor = TEMPORAL_PREPROCESSING_METHODS[method](method_options)

    n_components::Int = c["n_components"]
    if n_components ≤ 0
        throw(ArgumentError("`n_components` must be greater than `0`. Provided value: `$n_components`."))
    end

    lambda::Float64 = get(c, "lambda", 0.5)
    suffix::String = get(c, "suffix", "gaussian")

    return GaussianEncodingCard(
        type,
        label,
        method,
        temporal_preprocessor,
        input,
        n_components,
        lambda,
        suffix
    )
end

## SQLCard interface

sorting_vars(::GaussianEncodingCard) = String[]
grouping_vars(::GaussianEncodingCard) = String[]
input_vars(gec::GaussianEncodingCard) = [gec.input]
target_vars(::GaussianEncodingCard) = String[]
weight_var(::GaussianEncodingCard) = nothing
partition_var(::GaussianEncodingCard) = nothing
output_vars(gec::GaussianEncodingCard) = join_names.(gec.input, gec.suffix, 1:gec.n_components)

function train(::Repository, gec::GaussianEncodingCard, source::AbstractString; schema = nothing)
    μs = range(start = 0, step = 1 / gec.n_components, length = gec.n_components)
    σ = step(μs) * gec.lambda
    params = Dict("σ" => [σ], "d" => [gec.temporal_preprocessor.max])
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

    converted = map(1:gec.n_components) do i
        k = join_names(gec.input, gec.suffix, i)
        v = gaussian_transform(Get.transformed, Get(join_names("μ", i)), Get.σ, Get.d)
        return k => v
    end
    selection = vcat([id_var => Get(id_var)], converted)

    processed_input = gec.temporal_preprocessor(Get(gec.input))
    with_table(repository, params_tbl; schema) do tbl_name
        query = From(source) |>
            Partition() |>
            Select(id_var => Agg.row_number(), "transformed" => processed_input) |>
            Join(From(tbl_name), on = true) |>
            Select(args = selection)
        replace_table(repository, query, destination; schema)
    end
    return
end

## UI representation

function CardWidget(config::CardConfig{GaussianEncodingCard}, c::AbstractDict)
    methods = collect(keys(TEMPORAL_PREPROCESSING_METHODS))

    fields = vcat(
        [
            Widget("input", c),
            Widget("method", c; options = methods),
            Widget("n_components", c),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("lambda", c),
            Widget("suffix", c, value = "gaussian"),
        ]
    )

    return CardWidget(config.key, config.label, fields, OutputSpec("input", "suffix", "n_components"))
end
