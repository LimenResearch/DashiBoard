abstract type AbstractFilter end

struct IntervalFilter <: AbstractFilter
    colname::String
    interval::Interval
end

function Clause(f::IntervalFilter, prefix::AbstractString)
    (; colname, interval) = f

    params = Dict(
        prefix * "left" => leftendpoint(interval),
        prefix * "right" => rightendpoint(interval)
    )

    lcomp = ifelse(isleftclosed(interval), Fun.">=", Fun.">")
    rcomp = ifelse(isrightclosed(interval), Fun."<=", Fun."<")

    cond = Fun.and(
        lcomp(Get[colname], Var[prefix * "left"]),
        rcomp(Get[colname], Var[prefix * "right"]),
    )

    return Clause(Where(cond), params)
end

struct ListFilter <: AbstractFilter
    colname::String
    list::Vector{Any}
end

function Clause(f::ListFilter, prefix::AbstractString)
    (; colname, list) = f

    ks = [string(prefix, "value", i) for i in eachindex(list)]
    params = Dict{String, Any}(zip(ks, list))

    vars = [Var[k] for k in ks]
    cond = Fun.in(Get[colname], vars...)

    return Clause(Where(cond), params)
end

struct Filters
    intervals::Vector{IntervalFilter}
    lists::Vector{ListFilter}
end
