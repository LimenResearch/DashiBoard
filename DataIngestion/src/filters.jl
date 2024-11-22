struct Query
    node::SQLNode
    params::Dict{String, Any}
end

Query(node::SQLNode) = Query(node, Dict{String, Any}())

abstract type AbstractFilter end

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

get_filter(d::AbstractDict) = FILTER_TYPES[d["type"]](d)
get_filter(f::AbstractFilter) = f

struct Filters
    filters::Vector{AbstractFilter}
    function Filters(fs::AbstractVector)
        filters::Vector{AbstractFilter} = get_filter.(fs)
        return new(filters)
    end
end

function Query(filters::Filters; init)
    node, params = init, Dict{String, Any}()
    for (i, f) in enumerate(filters.filters)
        q = Query(f, string("filter", i, "_"))
        node = node |> q.node
        merge!(params, q.params)
    end
    return Query(node, params)
end

function select(filters::Filters, repo::Repository)
    (; node, params) = Query(filters, init = From(TABLE_NAMES.source))
    sql = render(get_catalog(repo), node)
    DBInterface.execute(
        Returns(nothing),
        repo,
        string("CREATE OR REPLACE TABLE ", TABLE_NAMES.selection, " AS\n", sql),
        pack(sql, params)
    )
end
