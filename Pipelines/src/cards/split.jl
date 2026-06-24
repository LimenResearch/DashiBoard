abstract type SplittingMethod end

order_error() = throw(ArgumentError("At least one sorter is required."))

# TODO: add randomized methods

struct PercentileMethod <: SplittingMethod
    percentile::Float64
    repeat::Float64
end

function get_sql(m::PercentileMethod)
    ε = eps(m.repeat)
    rk = Fun.fmod(m.repeat .* Agg.cume_dist() .- ε, 1) .+ ε
    return Fun.case(rk .≤ m.percentile, 1, 2)
end

function PercentileMethod(c::AbstractDict, has_order::Bool)
    has_order || order_error()
    percentile::Float64 = c["percentile"]
    repeat::Float64 = get(c, "repeat", 1.0)
    return PercentileMethod(percentile, repeat)
end

struct TilesMethod <: SplittingMethod
    tiles::Vector{Int}
    repeat::Int
    tail::Int
end

function get_sql(m::TilesMethod)
    n = length(m.tiles)
    N = m.repeat * n + m.tail
    vals = Fun.list_value(m.tiles...)
    # work around inconsistency in `%` operator and 1-based indexing in DuckDB
    return Fun.list_extract(vals, Fun."%"(Agg.ntile(N) .- 1, n) .+ 1)
end

function TilesMethod(c::AbstractDict, has_order::Bool)
    has_order || order_error()
    tiles::Vector{Int} = c["tiles"]
    repeat::Int = get(c, "repeat", 1)
    tail::Int = get(c, "tail", 0)
    return TilesMethod(tiles, repeat, tail)
end

const SPLITTING_METHODS = OrderedDict{String, DataType}(
    "percentile" => PercentileMethod,
    "tiles" => TilesMethod,
)

"""
    struct SplitCard <: Card
        type::String
        method::String
        splitter::SplittingMethod
        order_by::Vector{String}
        group_by::Vector{String}
        output::String
    end

Card to split the data into two groups according to a given function `splitter`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `percentile` argument, e.g. `percentile = 0.9`).
"""
struct SplitCard <: SQLCard
    type::String
    method::String
    splitter::SplittingMethod
    order_by::Vector{String}
    group_by::Vector{String}
    output::String
end

function get_metadata(sc::SplitCard)
    return StringDict(
        "type" => sc.type,
        "method" => sc.method,
        "method_options" => get_options(sc.splitter),
        "order_by" => sc.order_by,
        "group_by" => sc.group_by,
        "output" => sc.output,
    )
end

function SplitCard(c::AbstractDict)
    type::String = c["type"]
    order_by::Vector{String} = get(c, "order_by", String[])
    has_order = !isempty(order_by)
    group_by::Vector{String} = get(c, "group_by", String[])
    method::String = c["method"]
    method_options::StringDict = extract_options(c, "method", method)
    splitter::SplittingMethod = SPLITTING_METHODS[method](method_options, has_order)
    output::String = c["output"]
    return SplitCard(type, method, splitter, order_by, group_by, output)
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
        Select(id_var => Get(id_var), sc.output => get_sql(sc.splitter))

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
