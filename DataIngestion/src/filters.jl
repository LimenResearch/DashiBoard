abstract type AbstractFilter end

struct IntervalFilter <: AbstractFilter
    colname::String
    interval::Interval
end

function print_filter(io::IO, f::IntervalFilter, counter::Integer)
    (; colname, interval) = f

    l, r = leftendpoint(interval), rightendpoint(interval)
    lc, rc = isleftclosed(interval), isrightclosed(interval)

    print(io, colname, lc ? " >= " : " > ", "\$", counter += 1)
    print(io, " AND ")
    print(io, colname, rc ? " <= " : " < ", "\$", counter += 1)

    return Any[l, r]
end

struct ListFilter <: AbstractFilter
    colname::String
    list::Vector{Any}
end

function print_filter(io::IO, f::ListFilter, counter::Integer)
    (; colname, list) = f
    N = length(list)

    print(io, colname, " IN (")
    for i in 1:N
        print(io, "\$", counter += 1)
        i == N || print(io, ", ")
    end
    print(io, ")")

    return list
end

struct Filters
    intervals::Vector{IntervalFilter}
    lists::Vector{ListFilter}
end

get_filters(filters::Filters) = (filters.intervals, filters.lists)

function print_filters(io::IO, filters::Filters)
    print(io, "WHERE TRUE")
    params = Any[]
    foreach(get_filters(filters)) do fs
        for f in fs
            print(io, " AND ( ")
            ps = print_filter(io, f, length(params))
            print(io, " )")
            append!(params, ps)
        end
    end
    return params
end
