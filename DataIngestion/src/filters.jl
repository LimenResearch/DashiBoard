struct Query
    node::SQLNode
    params::Dict{String, Any}
end

Query(node::SQLNode) = Query(node, Dict{String, Any}())

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
    return IntervalFilter(colname, left .. right)
end

function Query(f::IntervalFilter, prefix::AbstractString)
    (; colname, interval) = f

    pleft, pright = string.(prefix, ("left", "right"))

    params = Dict(pleft => leftendpoint(interval), pright => rightendpoint(interval))

    cond = Fun.between(Get(colname), Var(pleft), Var(pright))

    return Query(Where(cond), params)
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

function Query(f::ListFilter, prefix::AbstractString)
    (; colname, list) = f

    ks = [string(prefix, "value", i) for i in eachindex(list)]
    params = Dict{String, Any}(zip(ks, list))

    cond = Fun.in(Get(colname), Var.(ks)...)

    return Query(Where(cond), params)
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

function Query(filters::AbstractVector; init)
    node, params = init, Dict{String, Any}()
    for (i, f) in enumerate(filters)
        q = Query(f, string("filter", i, "_"))
        node = node |> q.node
        merge!(params, q.params)
    end
    return Query(node, params)
end

"""
    select(filters::AbstractVector, repo::Repository)

Create a table with name `TABLE_NAMES.selection` within the database `repo.db`,
where `repo` is a  and [`Repository`](@ref).
The table `TABLE_NAMES.selection` is filled with rows from the table
`TABLE_NAMES.source` that are kept by the filters in `filters`.

Each filter should be an instance of [`AbstractFilter`](@ref).
"""
function select(filters::AbstractVector, repo::Repository)
    (; node, params) = Query(filters, init = From(TABLE_NAMES.source))
    sql = render(get_catalog(repo), node)
    DBInterface.execute(
        Returns(nothing),
        repo,
        string("CREATE OR REPLACE TABLE ", TABLE_NAMES.selection, " AS\n", sql),
        pack(sql, params)
    )
end
###################
# IntervalFilter for Date
struct DateIntervalFilter <: AbstractFilter
    colname::String
    interval::ClosedInterval{Date}
end

function Query(f::DateIntervalFilter, prefix::AbstractString)
    (; colname, interval) = f
    pleft, pright = string.(prefix, ("left", "right"))

    # Use plain values for Dates and handle casting in SQL
    params = Dict(pleft => string(leftendpoint(interval)), pright => string(rightendpoint(interval)))

    cond = Get(colname) .>= Fun.cast(Var(pleft), "DATE") .&& Get(colname) .<= Fun.cast(Var(pright), "DATE")

    return Query(Where(cond), params)
end

# IntervalFilter for Time
struct TimeIntervalFilter <: AbstractFilter
    colname::String
    interval::ClosedInterval{Time}
end

function Query(f::TimeIntervalFilter, prefix::AbstractString)
    (; colname, interval) = f
    pleft, pright = string.(prefix, ("left", "right"))

    # Use plain values for Times and handle casting in SQL
    params = Dict(pleft => string(leftendpoint(interval)), pright => string(rightendpoint(interval)))

    cond = Get(colname) .>= Fun.cast(Var(pleft), "TIME") .&& Get(colname) .<= Fun.cast(Var(pright), "TIME")

    return Query(Where(cond), params)
end

# IntervalFilter for DateTime
struct DateTimeIntervalFilter <: AbstractFilter
    colname::String
    interval::ClosedInterval{DateTime}
end

function Query(f::DateTimeIntervalFilter, prefix::AbstractString)
    (; colname, interval) = f
    pleft, pright = string.(prefix, ("left", "right"))

    # Use plain values for DateTimes and handle casting in SQL
    params = Dict(pleft => string(leftendpoint(interval)), pright => string(rightendpoint(interval)))

    cond = Get(colname) .>= Fun.cast(Var(pleft), "TIMESTAMP") .&& Get(colname) .<= Fun.cast(Var(pright), "TIMESTAMP")

    return Query(Where(cond), params)
end
