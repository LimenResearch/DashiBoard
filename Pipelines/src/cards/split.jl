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
        return Fun.case(Agg.percent_rank() .<= percentile, 1, 2)
    else
        throw(ArgumentError("method $method is not supported"))
    end
end

"""
    struct SplitCard <: Card
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
struct SplitCard <: Card
    splitter::SQLNode
    order_by::Vector{String}
    by::Vector{String}
    output::String
end

register_card("split", SplitCard)

function SplitCard(c::AbstractDict)
    splitter::SQLNode = get_splitter(c)
    order_by::Vector{String} = get(c, "order_by", String[])
    by::Vector{String} = get(c, "by", String[])
    output::String = c["output"]
    return SplitCard(splitter, order_by, by, output)
end

invertible(::SplitCard) = false

inputs(s::SplitCard)::Vector{String} = stringlist(s.order_by, s.by)
outputs(s::SplitCard)::Vector{String} = [s.output]

function train(::Repository, ::SplitCard, ::AbstractString; schema = nothing)
    return CardState()
end

function evaluate(
        repository::Repository,
        s::SplitCard,
        ::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    by = Get.(s.by)
    order_by = Get.(s.order_by)

    query = From(source) |>
        Partition(; by, order_by) |>
        Define(s.output => s.splitter)

    return replace_table(repository, query, destination; schema)
end

function CardWidget(
        ::Type{SplitCard};
        percentile = (min = 0, max = 1, step = 0.01),
    )

    options = ["percentile", "tiles"]

    fields = [
        Widget("method"; options),
        Widget("order_by"),
        Widget("by", required = false),
        Widget("output", value = "partition"),
        Widget(
            "percentile";
            percentile.min,
            percentile.max,
            percentile.step,
            visible = Dict("method" => ["percentile"])
        ),
        Widget("tiles", visible = Dict("method" => ["tiles"])),
    ]

    return CardWidget(; type = "split", label = "Split", output = OutputSpec("output"), fields)
end
