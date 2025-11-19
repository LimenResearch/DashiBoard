## AbstractDictHelper interface

abstract type AbstractDictHelper end

function _keys end
function splice end

isinstance(v, h::AbstractDictHelper) = v isa AbstractDict && issetequal(keys(v), _keys(h))

function _apply_helper(h::AbstractDictHelper, x, params::AbstractDict)
    return x isa Union{AbstractDict, AbstractVector} ? apply_helper(h, x, params) : x
end

function apply_helper(h::AbstractDictHelper, d::AbstractDict, params::AbstractDict)
    d1 = Dict{String, Any}()
    for (k, v) in pairs(d)
        d1[k] = if isinstance(v, h)
            splice(h) && throw(ArgumentError("Can only splice inside a list"))
            h(v, params)
        else
            _apply_helper(h, v, params)
        end
    end
    return d1
end

function apply_helper(h::AbstractDictHelper, vec::AbstractVector, params::AbstractDict)
    vec1 = Any[]
    for v in vec
        if isinstance(v, h)
            val = h(v, params)
            splice(h) ? append!(vec1, val) : push!(vec1, val)
        else
            push!(vec1, _apply_helper(h, v, params))
        end
    end
    return vec1
end

apply_helpers(hs, d::AbstractDict, ps) = foldl((dn, h) -> apply_helper(h, dn, ps), hs, init = d)

## Instances

struct VariableHelper <: AbstractDictHelper end

_keys(::VariableHelper) = Set(["-v"])
splice(::VariableHelper) = false

(::VariableHelper)(v, params) = params[v["-v"]]

struct SpliceHelper <: AbstractDictHelper end

_keys(::SpliceHelper) = Set(["-s"])
splice(::SpliceHelper) = true

(::SpliceHelper)(v, params) = params[v["-s"]]

struct NumberedHelper <: AbstractDictHelper end

_keys(::NumberedHelper) = Set(["-c", "-n"])
splice(::NumberedHelper) = true

(::NumberedHelper)(v, _) = string.(v["-c"], "_", 1:v["-n"])
