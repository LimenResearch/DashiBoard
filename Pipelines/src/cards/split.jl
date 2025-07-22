function get_splitter(c::AbstractDict)
    method::String = c["method"]

    # TODO: add randomized methods
    if method == "tiles"
        check_order(c)
        tiles::Vector{Int} = c["tiles"]
        N = length(tiles)
        return Fun.list_extract(Fun.list_value(tiles...), Agg.ntile(N))
    elseif method == "percentile"
        check_order(c)
        percentile::Float64 = c["percentile"]
        return Fun.case(Agg.percent_rank() .≤ percentile, 1, 2)
    else
        throw(ArgumentError("method $method is not supported"))
    end
end

"""
    struct SplitCard <: Card
        label::String
        splitter::SQLNode
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
    label::String
    splitter::SQLNode
    order_by::Vector{String}
    by::Vector{String}
    output::String
end

const SPLIT_CARD_CONFIG = CardConfig{SplitCard}(parse_toml_config("config", "split"))

function SplitCard(c::AbstractDict)
    label::String = card_label(c)
    splitter::SQLNode = get_splitter(c)
    order_by::Vector{String} = get(c, "order_by", String[])
    by::Vector{String} = get(c, "by", String[])
    output::String = c["output"]
    return SplitCard(label, splitter, order_by, by, output)
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
        Select(Get(id_var), sc.output => sc.splitter)

    replace_table(repository, query, destination; schema)
    return
end

## UI representation

function CardWidget(config::CardConfig{SplitCard}, options::AbstractDict)
    methods = ["percentile", "tiles"]
    percentile_options =
        get(options, "percentile", StringDict("min" => 0, "max" => 1, "step" => 0.01))

    fields = [
        Widget("method"; options = methods),
        Widget("order_by"),
        Widget("by", required = false),
        Widget("output", value = "partition"),
        Widget(
            "percentile",
            config.widget_configs,
            percentile_options,
            visible = Dict("method" => ["percentile"])
        ),
        Widget(
            "tiles",
            config.widget_configs,
            visible = Dict("method" => ["tiles"])
        ),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("output"))
end
