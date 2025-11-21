## AbstractDictHelper interface

abstract type AbstractDictHelper end

function extract_args(d::AbstractDict, ks::AbstractVector)
    return length(ks) == length(d) && ks ⊆ keys(d) ? Any[d[k] for k in ks] : nothing
end

extract_args(h::AbstractDictHelper, d::AbstractDict) = extract_args(d, h.keys)

struct SplicedValues
    vals::Vector{Any}
end

isspliced(x) = x isa SplicedValues

_apply_helpers(hs, x, params::AbstractDict, ::Integer) = x

function _apply_helpers(hs, x::SplicedValues, params::AbstractDict, height::Integer)
    vals = _apply_helpers(hs, x.vals, params, height)
    return SplicedValues(vals)
end

function _apply_helpers(hs, v::AbstractVector, params::AbstractDict, height::Integer)
    v1 = Any[]
    for x in v
        val = _apply_helpers(hs, x, params, height)
        isspliced(val) ? append!(v1, val.vals) : push!(v1, val)
    end
    return v1
end

function _apply_helpers_within(hs, d::AbstractDict, params::AbstractDict, height::Integer)
    d1 = StringDict()
    for (k, x) in pairs(d)
        val = _apply_helpers(hs, x, params, height)
        isspliced(val) ? throw(ArgumentError("Can only splice inside a list")) : (d1[k] = val)
    end
    return d1
end

function _apply_helpers(hs, d::AbstractDict, params::AbstractDict, height::Integer)
    d1 = _apply_helpers_within(hs, d, params, height)

    # check if `d1` is an instance of some helper,
    # in which case rerun `_apply_helpers` on the result
    # up to `max_rec` times
    for h in hs
        args = extract_args(h, d1)
        isnothing(args) && continue
        res, height = h(args, params), height - 1
        return height >= 0 ? _apply_helpers(hs, res, params, height) : res
    end
    return d1
end

function apply_helpers(hs, d::AbstractDict, params::AbstractDict; max_rec = 0)
    return _apply_helpers_within(hs, d, params, max_rec)
end

## Instances

@kwdef struct VariableHelper <: AbstractDictHelper
    keys::Vector{String} = ["-v"]
end

(::VariableHelper)((k,), params) = params[k]

@kwdef struct SpliceHelper <: AbstractDictHelper
    keys::Vector{String} = ["-s"]
end

(::SpliceHelper)((k,), params) = SplicedValues(params[k])

@kwdef struct RangeHelper <: AbstractDictHelper
    keys::Vector{String} = ["-r"]
end

(::RangeHelper)((n,), _) = range(1, n)

@kwdef struct JoinHelper <: AbstractDictHelper
    keys::Vector{String} = ["-j"]
end

function _join(xs, delim)
    iter = Iterators.product(map(Broadcast.broadcastable, xs)...)
    f = Fix2(join, delim)
    return collect(String, Iterators.map(f, iter))
end

(::JoinHelper)((xs,), _) = SplicedValues(_join(xs, "_"))

## Defaults

const DEFAULT_DICT_HELPERS = ScopedValue{Vector{AbstractDictHelper}}(
    [VariableHelper(), SpliceHelper(), RangeHelper(), JoinHelper()]
)

const DEFAULT_MAX_REC = ScopedValue{Int}(0)
