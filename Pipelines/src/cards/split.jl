abstract type SplittingMethod end

# TODO: add randomized methods

struct PercentileMethod <: SplittingMethod
    percentile::Float64
end

get_sql(s::PercentileMethod) = Fun.case(Agg.percent_rank() .≤ s.percentile, 1, 2)

function PercentileMethod(c::AbstractDict)
    check_order(c)
    percentile::Float64 = c["percentile"]
    return PercentileMethod(percentile)
end

struct TilesMethod <: SplittingMethod
    tiles::Vector{Int}
end

get_sql(s::TilesMethod) = Fun.list_extract(Fun.list_value(s.tiles...), Agg.ntile(length(s.tiles)))

function TilesMethod(c::AbstractDict)
    check_order(c)
    tiles::Vector{Int} = c["tiles"]
    return TilesMethod(tiles)
end

const SPLITTING_METHODS = OrderedDict{String, DataType}(
    "percentile" => PercentileMethod,
    "tiles" => TilesMethod,
)

"""
    struct SplitCard <: Card
        type::String
        label::String
        method::String
        splitter::SplittingMethod
        order_by::Vector{String}
        by::Vector{String}
        output::String
    end

Card to split the data into two groups according to a given function `splitter`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `percentile` argument, e.g. `percentile = 0.9`).
"""
struct SplitCard <: SQLCard
    type::String
    label::String
    method::String
    splitter::SplittingMethod
    order_by::Vector{String}
    by::Vector{String}
    output::String
end

const SPLIT_CARD_CONFIG = CardConfig{SplitCard}(parse_toml_config("config", "split"))

function get_metadata(sc::SplitCard)
    d = StringDict(
        "type" => sc.type,
        "label" => sc.label,
        "method" => sc.method,
        "order_by" => sc.order_by,
        "by" => sc.by,
        "output" => sc.output,
    )
    # TODO: decide on nesting vs no nesting (compare Cluster and DimRed)
    return merge!(d, get_options(sc.splitter))
end

function SplitCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    method::String = c["method"]
    splitter::SplittingMethod = SPLITTING_METHODS[method](c)
    order_by::Vector{String} = get(c, "order_by", String[])
    by::Vector{String} = get(c, "by", String[])
    output::String = c["output"]
    return SplitCard(type, label, method, splitter, order_by, by, output)
end

## SQLCard interface

sorting_vars(sc::SplitCard) = sc.order_by
grouping_vars(sc::SplitCard) = sc.by
input_vars(::SplitCard) = String[]
target_vars(::SplitCard) = String[]
weight_var(::SplitCard) = nothing
partition_var(::SplitCard) = nothing
output_vars(sc::SplitCard) = String[sc.output]

function train(::Repository, ::SplitCard, ::AbstractString; schema = nothing)
    return CardState()
end

function evaluate(
        repository::Repository,
        sc::SplitCard,
        ::CardState,
        (source, destination)::Pair,
        id_var::AbstractString;
        schema = nothing
    )
    order_by = Get.(sc.order_by)
    by = Get.(sc.by)
    selection = vcat(
        [id_var => Agg.row_number()],
        sc.order_by .=> order_by,
        sc.by .=> by,
    )

    query = From(source) |>
        Partition() |>
        Select(args = selection) |>
        Partition(; order_by, by) |>
        Select(Get(id_var), sc.output => get_sql(sc.splitter))

    replace_table(repository, query, destination; schema)
    return
end

## UI representation

function CardWidget(config::CardConfig{SplitCard}, options::AbstractDict)
    methods = collect(keys(SPLITTING_METHODS))
    percentile_options =
        get(options, "percentile", StringDict("min" => 0, "max" => 1, "step" => 0.01))

    fields = [
        Widget("method"; options = methods),
        Widget("order_by"),
        Widget("by", required = false),
        Widget("output", value = "partition"),
        Widget(
            config,
            "percentile",
            percentile_options,
            visible = Dict("method" => ["percentile"])
        ),
        Widget(
            config,
            "tiles",
            visible = Dict("method" => ["tiles"])
        ),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("output"))
end
