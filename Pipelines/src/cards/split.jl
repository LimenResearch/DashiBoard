"""
    struct SplitCard <: AbstractCard
        method::String
        order_by::Vector{String}
        by::Vector{String} = String[]
        output::String
        percentile::Union{Float64, Nothing} = nothing
        tiles::Vector{Int} = Int[]
    end

Card to split the data into two groups according to a given `method`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `percentile` argument, e.g. `percentile = 0.9`).
"""
@kwdef struct SplitCard <: AbstractCard
    method::String
    order_by::Vector{String}
    by::Vector{String} = String[]
    output::String
    percentile::Union{Float64, Nothing} = nothing
    tiles::Vector{Int} = Int[]
end

function inputs(s::SplitCard)
    i = Set{String}()
    union!(i, s.order_by)
    union!(i, s.by)
    return i
end

outputs(s::SplitCard) = Set([s.output])

function check_order(s::SplitCard)
    if isempty(s.order_by)
        throw(
            ArgumentError(
                """
                At least one sorter is required.
                """
            )
        )
    end
end

function splitter(s::SplitCard)
    method = s.method

    # TODO: add randomized methods
    if method == "tiles"
        N = length(s.tiles)
        return Fun.list_extract(Fun.list_value(s.tiles...), Agg.ntile(N))
    elseif method == "percentile"
        return Fun.case(Agg.percent_rank() .<= s.percentile, 1, 2)
    else
        throw(ArgumentError("method $method is not supported"))
    end
end

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

    check_order(s)

    by = Get.(s.by)
    order_by = Get.(s.order_by)

    query = From(source) |>
        Partition(; by, order_by) |>
        Define(s.output => splitter(s))

    replace_table(repo, query, dest; schema)
end

function CardWidget(
        ::Type{SplitCard};
        percentile = (min = 0, max = 1, step = 0.01),
    )

    options = ["percentile", "tiles"]

    fields = [
        SelectWidget("method"; options),
        SelectWidget("order_by"),
        SelectWidget("by"),
        TextWidget("output", value = "partition"),
        NumberWidget(
            "percentile";
            percentile.min,
            percentile.max,
            percentile.step,
            visible = Dict("method" => ["percentile"])
        ),
        SelectWidget("tiles", visible = Dict("method" => ["tiles"]))
    ]

    return CardWidget(; type = "split", label = "Split", output = OutputSpec("output"), fields)
end
