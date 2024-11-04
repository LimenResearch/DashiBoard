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

    cond = Fun.in(Get(colname), Var.(ks)...)

    return Query(Where(cond), params)
end

struct Filters
    intervals::Vector{IntervalFilter}
    lists::Vector{ListFilter}
end

Filters(; intervals = IntervalFilter[], lists = ListFilter[]) = Filters(intervals, lists)

function Query(filters::Filters; init)
    qs = vcat(
        [Query(f, string("interval", i)) for (i, f) in enumerate(filters.intervals)],
        [Query(f, string("list", i)) for (i, f) in enumerate(filters.lists)],
    )
    node, params = init, Dict{String, Any}()
    for q in qs
        node = node |> q.node
        merge!(params, q.params)
    end
    return Query(node, params)
end

function select(repo::Repository, filters::Filters)
    (; node, params) = Query(filters, init = From(TABLE_NAMES.source))
    sql = render(get_catalog(repo), node)
    DBInterface.execute(
        Returns(nothing),
        repo,
        string("CREATE OR REPLACE TABLE ", TABLE_NAMES.selection, " AS\n", sql),
        pack(sql, params)
    )
end
