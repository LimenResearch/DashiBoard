abstract type AbstractDataFormat{N} end

struct SpatialFormat{N} <: AbstractDataFormat{N} end

SpatialFormat(x) = SpatialFormat{x}()

const FlatFormat = SpatialFormat{0}

defaultformat(::NTuple{N, Int}) where {N} = SpatialFormat{N - 1}()

struct FourierFormat{N} <: AbstractDataFormat{N} end

struct Reshaper{T}
    format::T
end

instantiate(r::Reshaper, sz, fmt) = reshaper(r.format, sz, fmt)

reshaper(::T, sz, ::T) where {T <: AbstractDataFormat} = nothing, sz, T()

reshaper(::FlatFormat, sz, ::FlatFormat) = nothing, sz, FlatFormat()

reshaper(::FlatFormat, sz, ::SpatialFormat{N}) where {N} = flatten, (prod(sz),), FlatFormat()

function reshaper(::SpatialFormat{N}, (feats,), ::FlatFormat) where {N}
    factors = factor(Vector, feats)
    spatial = ntuple(n -> get(factors, n, 1), N)
    feats′ = div(feats, prod(spatial))
    size = (spatial..., feats′)
    return Fix2(unflatten, size), size, SpatialFormat{N}()
end

unflatten(x::AbstractMatrix, sz) = reshape(x, sz..., last(size(x)))

function reshaper(::FourierFormat{N}, (sp..., f), ::SpatialFormat{N}) where {N}
    # TODO: choose default
    pad_ratio = get(MODEL_CONTEXT[], :pad_ratio, fill(1.0, N))
    sz′ = (f, sp...)
    return Fourier(Tuple(pad_ratio)), sz′, FourierFormat{N}()
end

function reshaper(::FourierFormat{N}, (feats,), ::FlatFormat) where {N}
    res, size, _ = reshaper(SpatialFormat{N}(), (feats,), FlatFormat())
    res′, size′ = reshaper(FourierFormat{N}(), size, SpatialFormat{N}())
    return Flux.Chain(res, res′), size′, FourierFormat{N}()
end

function reshaper(::SpatialFormat{N}, (f, sp...), ::FourierFormat{N}) where {N}
    sz′ = (sp..., f)
    return InvFourier(), sz′, SpatialFormat{N}()
end

function reshaper(::FlatFormat, size, ::FourierFormat{N}) where {N}
    return Flux.Chain(InvFourier(), flatten), prod(size), FlatFormat()
end
