## AbstractDictHelper interface

abstract type AbstractDictHelper end

function _keys end

isinstance(v, h::AbstractDictHelper) = v isa AbstractDict && issetequal(keys(v), _keys(h))

struct SplicedValues
    vals::Vector{Any}
end

isspliced(x) = x isa SplicedValues

function _apply_helpers_nested(hs, x, params)
    x1 = _apply_helpers(hs, x, params)
    for h in hs
        isinstance(x1, h) && return _apply_helpers(hs, h(x1, params), params)
    end
    return x1
end

_apply_helpers(hs, x, params::AbstractDict) = x

function _apply_helpers(hs, x::SplicedValues, params::AbstractDict)
    vals = _apply_helpers(hs, x.vals, params)
    return SplicedValues(vals)
end

function _apply_helpers(hs, d::AbstractDict, params::AbstractDict)
    d1 = Dict{String, Any}()
    for (k, x) in pairs(d)
        val = _apply_helpers_nested(hs, x, params)
        isspliced(val) ? throw(ArgumentError("Can only splice inside a list")) : (d1[k] = val)
    end
    return d1
end

function _apply_helpers(hs, v::AbstractVector, params::AbstractDict)
    v1 = Any[]
    for x in v
        val = _apply_helpers_nested(hs, x, params)
        isspliced(val) ? append!(v1, val.vals) : push!(v1, val)
    end
    return v1
end

apply_helpers(hs, d::AbstractDict, params::AbstractDict) = _apply_helpers(hs, d, params)

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
