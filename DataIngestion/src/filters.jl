struct Condition
    pred::SQLNode
    params::Dict{String, Any}
end

get_pred(cond::Condition) = cond.pred
get_params(cond::Condition) = cond.params

"""
    abstract type AbstractFilter end

Abstract supertype to encompass all possible filters.

Current implementations:

- [`IntervalFilter`](@ref),
- [`ListFilter`](@ref).
"""
abstract type AbstractFilter end

"""
    struct IntervalFilter{T} <: AbstractFilter
        colname::String
        interval::ClosedInterval{T}
    end

Object to retain only those rows for which the variable `colname` lies inside the `interval`.
"""
struct IntervalFilter{T} <: AbstractFilter
    colname::String
    interval::ClosedInterval{T}
end

function IntervalFilter(d::AbstractDict)
    colname, interval = d["colname"], d["interval"]
    left, right = interval["min"], interval["max"]
    return IntervalFilter(colname, ClosedInterval(left, right))
end

function Condition(f::IntervalFilter, prefix::AbstractString)
    (; colname, interval) = f

    pleft, pright = string.(prefix, ("left", "right"))
    params = Dict(pleft => leftendpoint(interval), pright => rightendpoint(interval))
    pred = Fun.between(Get(colname), Var(pleft), Var(pright))

    return Condition(pred, params)
end

"""
    struct ListFilter{T} <: AbstractFilter
        colname::String
        list::Vector{T}
    end

Object to retain only those rows for which the variable `colname` belongs to a `list` of options.
"""
struct ListFilter{T} <: AbstractFilter
    colname::String
    list::Vector{T}
end

function ListFilter(d::AbstractDict)
    colname, list = d["colname"], d["list"]
    T = eltype(list)
    return ListFilter{T}(colname, list)
end

function Condition(f::ListFilter, prefix::AbstractString)
    (; colname, list) = f

    ks = string.(prefix, "value", eachindex(list))
    params = Dict{String, Any}(zip(ks, list))
    pred = Fun.in(Get(colname), Var.(ks)...)

    return Condition(pred, params)
end

const FILTER_TYPES = Dict(
    "interval" => IntervalFilter,
    "list" => ListFilter,
)

"""
    get_filter(d::AbstractDict)

Generate an [`AbstractFilter`](@ref) based on a configuration dictionary.
"""
get_filter(d::AbstractDict) = FILTER_TYPES[d["type"]](d)

"""
    select(repository::Repository, filters::AbstractVector; schema = nothing)

Create a table with name `TABLE_NAMES.selection` within the database `repository.db`,
where `repository` is a [`Repository`](@ref).
The table `TABLE_NAMES.selection` is filled with rows from the table
`TABLE_NAMES.source` that are kept by the filters in `filters`.

Each filter should be an instance of [`AbstractFilter`](@ref).
"""
function select(repository::Repository, filters::AbstractVector; schema = nothing)
    cs = [Condition(f, string("filter", i, "_")) for (i, f) in enumerate(filters)]
    params = mapfoldl(get_params, merge!, cs, init = Dict{String, Any}())
    pred = Fun.and(Iterators.map(get_pred, cs)...)
    node = From(TABLE_NAMES.source) |> Where(pred)
    return replace_table(repository, node, params, TABLE_NAMES.selection; schema)
end
