abstract type AbstractFormat{N} end

abstract type ClassicalFormat{N} <: AbstractFormat{N} end

struct SpatialFormat{N} <:ClassicalFormat{N} end

struct FlatFormat <:ClassicalFormat{0} end

defaultformat(::NTuple{N, Int}) where {N} = SpatialFormat{N - 1}()

defaultformat(::Tuple{Int}) = FlatFormat()

struct Reshaper end

function instantiate(
        ::Reshaper, inputsize::Tuple, inputformat::AbstractFormat;
        outputsize::Maybe{Tuple} = nothing, outputformat::Maybe{AbstractFormat} = nothing
    )

    return reshaper(inputformat, outputformat, inputsize, outputsize)
end

unflatten(x::AbstractMatrix, sz) = reshape(x, sz..., last(size(x)))

reshaper(::SpatialFormat{N}, ::FlatFormat, isz, _) where {N} = flatten, (prod(isz),), FlatFormat()

function reshaper(::FlatFormat, ::SpatialFormat{N}, (feats,), _) where {N}
    factors = factor(Vector, feats)
    spatial = ntuple(n -> get(factors, n, 1), N)
    feats′ = div(feats, prod(spatial))
    size = (spatial..., feats′)
    return Fix2(unflatten, size), size, SpatialFormat{N}()
end

