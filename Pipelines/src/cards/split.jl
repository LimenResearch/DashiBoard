"""
    struct SplitCard <: AbstractCard
        method::String
        order_by::Vector{String}
        by::Vector{String} = String[]
        output::String
        p::Float64 = NaN
        tiles::Vector{Int} = Int[]
    end

Card to split the data into two groups according to a given `method`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `p` argument, e.g. `p = 0.9`).
"""
@kwdef struct SplitCard <: AbstractCard
    method::String
    order_by::Vector{String}
    by::Vector{String} = String[]
    output::String
    p::Float64 = NaN
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
        return Fun.case(Agg.percent_rank() .<= s.p, 1, 2)
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

    methods = ["percentile", "tiles"]

    fields = [
        MethodWidget(methods),
        OrderWidget(),
        GroupWidget(),
        TextWidget(
            key = "output",
            label = "Output",
            placeholder = "Select output name...",
            value = "partition",
            type = "text",
        ),
        NumberWidget(;
            key = "p",
            label = "Percentile",
            placeholder = "Select percentile value...",
            percentile.min,
            percentile.max,
            percentile.step,
            conditional = Dict("method" => ["percentile"])
        ),
        SelectWidget(
            key = "tiles",
            label = "Tiles",
            placeholder = "Select tiles...",
            multiple = true,
            type = "number",
            options = [1, 2],
            conditional = Dict("method" => ["tiles"])
        ),
    ]

    return CardWidget(; type = "split", label = "Split", output = OutputSpec("output"), fields)
end
