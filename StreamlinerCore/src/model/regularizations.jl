## L¹ and L² norms

struct Regularization{M}
    method::M
    lambda::Float32
end

Regularization(method::M, lambda::Real) where {M} = Regularization(method, Float32(lambda))

(r::Regularization)(m) = r.lambda * r.method(m)

_l1(x::AbstractArray{<:Number}) = sum(abs, x)
_l2(x::AbstractArray{<:Number}) = sum(abs2, x)

l1(m) = sum(_l1, trainables(m))
l2(m) = sum(_l2, trainables(m))

# work-around for https://github.com/FluxML/Zygote.jl/issues/1529

abs′(x::Real) = sign(x)
abs′(x::Complex, Ω) = x / ifelse(iszero(x), one(Ω), Ω)

function ChainRulesCore.rrule(::typeof(_l1), x::AbstractArray{<:Real})
    _l1_pullback(ȳ) = NoTangent(), unthunk(ȳ) .* abs′.(x)

    return _l1(x), _l1_pullback
end

function ChainRulesCore.rrule(::typeof(_l1), x::AbstractArray{<:Complex})
    Ω = abs.(x)

    _l1_pullback(z̄) = NoTangent(), unthunk(z̄) .* abs′.(x, Ω)

    return sum(Ω), _l1_pullback
end

# Methods for parsing

function get_regularization(config::AbstractDict)
    f = PARSER[].regularizations[config[:name]]
    return Regularization(f, config[:lambda])
end

function get_regularizations(config::AbstractDict)
    configs = get_configs(config, :regularizations)
    return Tuple(get_regularization.(configs))
end
