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

inputs(s::SplitCard) = union(s.order_by, s.by)

outputs(s::SplitCard) = [s.output]

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

    if method == "tiles"
        N = length(s.tiles)
        return Fun.list_extract(Fun.list_value(s.tiles...), Agg.ntile(N))
    elseif method == "percentile"
        return Fun.case(Agg.percent_rank() .<= s.p, 1, 2)
    else
        throw(ArgumentError("method $method is not supported"))
    end
end

function train(::SplitCard, ::Repository, ::AbstractString; schema = nothing)
    return nothing
end

function evaluate(
        s::SplitCard,
        ::Nothing,
        repo::Repository,
        (source, target)::StringPair;
        schema = nothing
    )

    check_order(s)

    by = Get.(s.by)
    order_by = Get.(s.order_by)

    query = From(source) |>
        Partition(; by, order_by) |>
        Define(s.output => splitter(s))

    replace_table(repo, query, target; schema)
end
