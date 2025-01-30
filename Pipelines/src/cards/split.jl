"""
    struct SplitCard <: AbstractCard
        method::SQLNode
        order_by::Vector{String}
        by::Vector{String}
        output::String
    end

Card to split the data into two groups according to a given `method`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `percentile` argument, e.g. `percentile = 0.9`).
"""
struct SplitCard <: AbstractCard
    method::SQLNode
    order_by::Vector{String}
    by::Vector{String}
    output::String
end

function splitter(c::Config)
    method = c.method

    # TODO: add randomized methods
    if method == "tiles"
        check_order(c)
        tiles::Vector{Int} = c.tiles
        N = length(tiles)
        return Fun.list_extract(Fun.list_value(tiles...), Agg.ntile(N))
    elseif method == "percentile"
        check_order(c)
        percentile::Float64 = c.percentile
        return Fun.case(Agg.percent_rank() .<= percentile, 1, 2)
    else
        throw(ArgumentError("method $method is not supported"))
    end
end

function SplitCard(c::Config)
    method::SQLNode = splitter(c)
    order_by::Vector{String} = get(c, :order_by, String[])
    by::Vector{String} = get(c, :by, String[])
    output::String = c.output
    return SplitCard(method, order_by, by, output)
end

inputs(s::SplitCard) = stringset(s.order_by, s.by)

outputs(s::SplitCard) = stringset(s.output)

function train(::Repository, ::SplitCard, ::AbstractString; schema = nothing)
    return nothing
end

function evaluate(
        repo::Repository,
        s::SplitCard,
        ::Nothing,
        (source, dest)::Pair;
        schema = nothing
    )

    by = Get.(s.by)
    order_by = Get.(s.order_by)

    query = From(source) |>
        Partition(; by, order_by) |>
        Define(s.output => s.method)

    replace_table(repo, query, dest; schema)
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
