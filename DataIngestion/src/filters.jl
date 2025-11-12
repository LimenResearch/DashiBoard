struct Condition
    pred::SQLNode
    params::StringDict
end

get_pred(cond::Condition) = cond.pred
get_params(cond::Condition) = cond.params

"""
    abstract type Filter end

Abstract supertype to encompass all possible filters.

Current implementations:

- [`IntervalFilter`](@ref),
- [`ListFilter`](@ref).
"""
abstract type Filter end

"""
    Filter(d::AbstractDict)

Generate a [`Filter`](@ref) based on a configuration dictionary.
"""
Filter(d::AbstractDict) = FILTER_TYPES[d["type"]](d)

"""
    struct IntervalFilter{T} <: Filter
        colname::String
        interval::ClosedInterval{T}
    end

Object to retain only those rows for which the variable `colname` lies inside the `interval`.
"""
struct IntervalFilter{T} <: Filter
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
    struct ListFilter{T} <: Filter
        colname::String
        list::Vector{T}
    end

Object to retain only those rows for which the variable `colname` belongs to a `list` of options.
"""
struct ListFilter{T} <: Filter
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
    params = StringDict(zip(ks, list))
    pred = Fun.in(Get(colname), Var.(ks)...)

    return Condition(pred, params)
end

const FILTER_TYPES = Dict(
    "interval" => IntervalFilter,
    "list" => ListFilter,
)

"""
    select(
        repository::Repository,
        filters::AbstractVector,
        (src, tgt)::Pair = "$(TABLE_NAMES.source)" => "$(TABLE_NAMES.selection)";
        schema = nothing
    )

Create a table with name `tgt` (defaults to "$(TABLE_NAMES.selection)")
within the schema `schema` (defaults to main schema) inside `repository.db`,
where `repository` is a [`Repository`](@ref).
The table `tgt` is filled with rows from the table `src` (defaults to "$(TABLE_NAMES.source)")
that are kept by the filters in `filters`.

Each filter should be an instance of [`Filter`](@ref).
"""
function select(
        repository::Repository,
        filters::AbstractVector,
        (src, tgt)::Pair = TABLE_NAMES.source => TABLE_NAMES.selection;
        schema = nothing
    )
    cs = [Condition(f, string("filter", i, "_")) for (i, f) in enumerate(filters)]
    params = mapfoldl(get_params, merge!, cs, init = StringDict())
    pred = Fun.and(Iterators.map(get_pred, cs)...)
    node = From(src) |> Where(pred)
    return replace_table(repository, node, params, tgt; schema)
end
