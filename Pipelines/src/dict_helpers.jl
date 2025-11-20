## AbstractDictHelper interface

abstract type AbstractDictHelper end

function _keys end

isinstance(v, h::AbstractDictHelper) = v isa AbstractDict && issetequal(keys(v), _keys(h))

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
        if isinstance(d1, h)
            res, height = h(d1, params), height - 1
            return height >= 0 ? _apply_helpers(hs, res, params, height) : res
        end
    end
    return d1
end

function apply_helpers(hs, d::AbstractDict, params::AbstractDict; max_rec = 0)
    return _apply_helpers_within(hs, d, params, max_rec)
end

## Instances

struct VariableHelper <: AbstractDictHelper end

_keys(::VariableHelper) = Set(["-v"])

(::VariableHelper)(v, params) = params[v["-v"]]

struct SpliceHelper <: AbstractDictHelper end

_keys(::SpliceHelper) = Set(["-s"])

(::SpliceHelper)(v, params) = SplicedValues(params[v["-s"]])

struct NumberedHelper <: AbstractDictHelper end

_keys(::NumberedHelper) = Set(["-c", "-n"])

(::NumberedHelper)(v, _) = SplicedValues(string.(v["-c"], "_", 1:v["-n"]))

## Defaults

const DEFAULT_DICT_HELPERS = ScopedValue{Vector{AbstractDictHelper}}(
    [VariableHelper(), SpliceHelper(), NumberedHelper()]
)

const DEFAULT_MAX_REC = ScopedValue{Int}(0)
