abstract type AbstractFilter end

struct IntervalFilter{T} <: AbstractFilter
    colname::String
    interval::ClosedInterval{T}
end

function Query(f::IntervalFilter, prefix::AbstractString)
    (; colname, interval) = f

    pleft, pright = string.(prefix, ("left", "right"))

    params = Dict(pleft => leftendpoint(interval), pright => rightendpoint(interval))

    cond = Fun.between(Get(colname), Var(pleft), Var(pright))

    return Query(Where(cond), params)
end

struct ListFilter{T} <: AbstractFilter
    colname::String
    list::Vector{T}
end

function Query(f::ListFilter, prefix::AbstractString)
    (; colname, list) = f

    ks = [string(prefix, "value", i) for i in eachindex(list)]
    params = Dict{String, Any}(zip(ks, list))

    vars = [Var(k) for k in ks]
    cond = Fun.in(Get(colname), vars...)

    return Query(Where(cond), params)
end

struct Filters
    intervals::Vector{IntervalFilter}
    lists::Vector{ListFilter}
end

struct QuerySpec
    table::String
    filters::Filters
    select::Vector{String}
end

function Query(q::QuerySpec)
    queries = vcat(
        [Query(From(q.table))],
        [Query(f, string("interval", i)) for (i, f) in enumerate(q.filters.intervals)],
        [Query(f, string("list", i)) for (i, f) in enumerate(q.filters.lists)],
        [Query(Select(args = [Get(colname) for colname in q.select]))]
    )
    return chain(queries)
end
