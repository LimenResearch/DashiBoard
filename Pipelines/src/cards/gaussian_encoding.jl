abstract type TemporalProcessingMethod <: AbstractMethod end

@kwarg struct IdentityMethod <: TemporalProcessingMethod
    max::Float64 = 1.0
end
(::IdentityMethod)(x::SQLNode) = x

@kwarg struct DayOfWeekMethod <: TemporalProcessingMethod
    max::Float64 = 7.0
end
(::DayOfWeekMethod)(x::SQLNode) = Fun.dayofweek(x)

@kwarg struct DayOfYearMethod <: TemporalProcessingMethod
    max::Float64 = 366.0
end
(::DayOfYearMethod)(x::SQLNode) = Fun.dayofyear(x)

@kwarg struct HourOfDayMethod <: TemporalProcessingMethod
    max::Float64 = 24.0
end
(::HourOfDayMethod)(x::SQLNode) = Fun.hour(x)

@kwarg struct MinuteOfDayMethod <: TemporalProcessingMethod
    max::Float64 = 1440.0
end
(::MinuteOfDayMethod)(x::SQLNode) = @. hour(x) * 60 + minute(x)

@kwarg struct MinuteOfHourMethod <: TemporalProcessingMethod
    max::Float64 = 60.0
end
(::MinuteOfHourMethod)(x::SQLNode) = @. minute(x)

const TEMPORAL_PREPROCESSING_METHODS = OrderedDict{String, DataType}(
    "identity" => IdentityMethod,
    "dayofweek" => DayOfWeekMethod,
    "dayofyear" => DayOfYearMethod,
    "hourofday" => HourOfDayMethod,
    "minuteofday" => MinuteOfDayMethod,
    "minuteofhour" => MinuteOfHourMethod,
)

@options TemporalProcessingMethod TEMPORAL_PREPROCESSING_METHODS "identity"

"""
    struct GaussianEncodingCard <: Card

Defines a card for applying Gaussian transformations to a specified column.

Fields:
- `method::TemporalProcessingMethod`: Tranformation to process a given column (see below).
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
  - `"dayofweek"`: Applies the SQL `dayofweek` function.
  - `"dayofyear"`: Applies the SQL `dayofyear` function.
  - `"hourofday"`: Applies the SQL `hour` function.
  - `"minuteofhour"`: Computes the minute within the hour.
  - `"minuteofday"`: Computes the minute within the day.

Train:
- Returns: `SimpleTable` (`OrderedDict{String, AbstractVector}`) with Gaussian parameters:
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
@kwarg struct GaussianEncodingCard{M <: TemporalProcessingMethod} <: SQLCard
    method::M = IdentityMethod()
    input::String & (dashi = JSON_VARIABLE,)
    n_components::Int & (dashi = json_integer(minimum = 1),)
    lambda::Float64 = 0.5 & (dashi = json_number(exclusiveMinimum = 0),)
    suffix::String = "gaussian" & (dashi = json_string(minLength = 1),)
end

## SQLCard interface

SourceVariables(gec::GaussianEncodingCard) = SourceVariables(; inputs = [gec.input])

OutputVariables(gec::GaussianEncodingCard) = OutputVariables(join_names.(gec.input, gec.suffix, 1:gec.n_components))

function train(
        ::Repository, gec::GaussianEncodingCard, ::AbstractString, ::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    μs = range(start = 0, step = 1 / gec.n_components, length = gec.n_components)
    σ = step(μs) * gec.lambda
    params = SimpleTable("σ" => [σ], "d" => [gec.method.max])
    for (i, μ) in enumerate(μs)
        params["μ_$i"] = [μ]
    end
    return CardState(content = jldserialize(params))
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
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    params_tbl = jlddeserialize(state.content)

    converted = map(1:gec.n_components) do i
        k = join_names(gec.input, gec.suffix, i)
        v = gaussian_transform(Get.transformed, Get(join_names("μ", i)), Get.σ, Get.d)
        return k => v
    end
    selection = vcat([id_var => Get._id], converted)

    processed_input = gec.method(Get(gec.input))
    with_table(repository, params_tbl; schema) do tbl_name
        query = From(source) |>
            Select("_id" => Get(id_var), "transformed" => processed_input) |>
            Join(From(tbl_name), on = true) |>
            Select(args = selection)
        replace_table(repository, query, destination; schema)
    end
    return map(first, converted)
end

## UI representation

function CardWidget(
        ::Type{GaussianEncodingCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

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

    return CardWidget(key, fields, OutputSpec("input", "suffix", "n_components"))
end
