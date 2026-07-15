abstract type SplittingMethod <: AbstractMethod end

abstract type OrderedSplittingMethod <: SplittingMethod end

abstract type UnorderedSplittingMethod <: SplittingMethod end

order_error() = throw(ArgumentError("At least one sorter is required."))

# TODO: add unordered methods

@tags struct PercentileMethod <: OrderedSplittingMethod
    percentile::Float64 & (dashi = json_number(minimum = 0, maximum = 1),)
end

get_sql(m::PercentileMethod) = Fun.case(Agg.percent_rank() .≤ m.percentile, 1, 2)

@kwarg struct TilesMethod <: OrderedSplittingMethod
    tiles::Vector{Int} & (
        dashi = json_array(items = json_integer(enum = [1, 2]), minItems = 1),
    )
    repeat::Int = 1 & (dashi = json_integer(minimum = 1),)
    tail::Int = 0 & (dashi = json_integer(minimum = 0),)
end

function get_sql(m::TilesMethod)
    n = length(m.tiles)
    N = m.repeat * n + m.tail
    vals = Fun.list_value(m.tiles...)
    # work around inconsistency in `%` operator and 1-based indexing in DuckDB
    return Fun.list_extract(vals, Fun."%"(Agg.ntile(N) .- 1, n) .+ 1)
end

const SPLITTING_METHODS = OrderedDict{String, DataType}(
    "percentile" => PercentileMethod,
    "tiles" => TilesMethod,
)

@options SplittingMethod SPLITTING_METHODS

"""
    struct SplitCard{M <: SplittingMethod} <: SQLCard
        method::M
        order_by::Vector{String} = String[]
        group_by::Vector{String} = String[]
        output::String = "partition"
    end

Card to split the data into two groups according to a given `method`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `percentile` argument, e.g. `percentile = 0.9`).
"""
@kwarg struct SplitCard{M <: SplittingMethod} <: SQLCard
    method::M
    order_by::Vector{String} & (dashi = JSON_NONEMPTY_VARIABLES,) # TODO: weaken requirement
    group_by::Vector{String} = String[] & (dashi = JSON_VARIABLES,)
    output::String = "partition" & (dashi = json_string(minLength = 1),)

    @optional_type_params function SplitCard{M}(
            method::M, order_by::AbstractVector, group_by::AbstractVector, output::AbstractString
        ) where {M <: SplittingMethod}
        (method isa OrderedSplittingMethod) && isempty(order_by) && order_error()
        return new{M}(method, order_by, group_by, output)
    end
end

## SQLCard interface

SourceVariables(sc::SplitCard) = SourceVariables(; sc.order_by, sc.group_by)

OutputVariables(sc::SplitCard) = OutputVariables([sc.output])

function train(
        ::Repository, ::SplitCard, ::AbstractString, ::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    return CardState()
end

function evaluate(
        repository::Repository,
        sc::SplitCard,
        ::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    query = From(source) |>
        Partition(; order_by = Get.(sc.order_by), by = Get.(sc.group_by)) |>
        Select(id_var => Get(id_var), sc.output => get_sql(sc.method))

    replace_table(repository, query, destination; schema)
    return [sc.output]
end

## UI representation

function CardWidget(
        ::Type{SplitCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(SPLITTING_METHODS))

    fields = vcat(
        [
            Widget("method", c; options = methods),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("order_by", c),
            Widget("group_by", c, required = false),
            Widget("output", c, value = "partition"),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
