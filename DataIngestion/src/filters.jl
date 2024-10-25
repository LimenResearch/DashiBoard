abstract type AbstractFilter end

struct IntervalFilter{T} <: AbstractFilter
    colname::String
    interval::ClosedInterval{T}
end

function ParametricNode(f::IntervalFilter, prefix::AbstractString)
    (; colname, interval) = f

    pleft, pright = string.(prefix, ("left", "right"))

    params = Dict(pleft => leftendpoint(interval), pright => rightendpoint(interval))

    cond = Fun.between(Get(colname), Var(pleft), Var(pright))

    return ParametricNode(Where(cond), params)
end

struct ListFilter{T} <: AbstractFilter
    colname::String
    list::Vector{T}
end

function ParametricNode(f::ListFilter, prefix::AbstractString)
    (; colname, list) = f

    ks = [string(prefix, "value", i) for i in eachindex(list)]
    params = Dict{String, Any}(zip(ks, list))

    cond = Fun.in(Get(colname), Var.(ks)...)

    return ParametricNode(Where(cond), params)
end

struct Filters
    intervals::Vector{IntervalFilter}
    lists::Vector{ListFilter}
end

struct FilterSelect
    filters::Filters
    select::Vector{String}
end

function Query(fs::FilterSelect, prefix::AbstractString = "")
    (; filters, select) = fs
    nodes = vcat(
        [ParametricNode(f, string(prefix, "interval", i)) for (i, f) in enumerate(filters.intervals)],
        [ParametricNode(f, string(prefix, "list", i)) for (i, f) in enumerate(filters.lists)],
        [ParametricNode(Select(args = [Get(colname) for colname in select]))]
    )
    return Query(nodes)
end
