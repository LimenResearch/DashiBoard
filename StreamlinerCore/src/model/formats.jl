abstract type AbstractFormat{N} end

abstract type ClassicalFormat{N} <: AbstractFormat{N} end

struct SpatialFormat{N} <:ClassicalFormat{N} end

struct FlatFormat <:ClassicalFormat{0} end

struct Shape{N, T <: Maybe{AbstractFormat{N}}}
    format::T
    features::Maybe{Int}
    shape::Maybe{Dims{N}}

    function Shape{N}(
            format::T,
            features::Maybe{Integer},
            shape::Maybe{NTuple{N, Integer}}
        ) where {N, T <: Maybe{AbstractFormat{N}}}

        return new{N, T}(format, features, shape)
    end
end

function Shape(
        format::AbstractFormat{N},
        features::Maybe{Integer} = nothing,
        shape::Maybe{NTuple{N, Integer}} = nothing
    ) where {N}

    return Shape{N}(format, features, shape)
end

function Shape(features::Integer, shape::NTuple{N, Integer} = ()) where {N}
    format = N == 0 ? FlatFormat() : SpatialFormat{N}()
    return Shape{N}(format, features, shape)
end

struct Formatter end

const formatter = Formatter()

function instantiate(::Formatter, input::Shape, output::Shape)
    return if input.format === output.format
        nothing, input
    else
        reformat(input.format, output.format, input, output)
    end
end

function unflatten(x::AbstractMatrix, s::Shape)
    (; features, shape) = s
    _..., mb = size(x)
    return reshape(x, shape..., features, mb)
end

function reformat(::SpatialFormat{N}, ::FlatFormat, input::Shape, output::Shape) where {N}
    features = input.features * prod(input.shape)
    return flatten, Shape(features)
end

function reformat(::FlatFormat, ::SpatialFormat{N}, input::Shape, output::Shape) where {N}
    factors = factor(Vector, input.features)
    shape = ntuple(n -> get(factors, n, 1), N)
    features = div(input.features, prod(shape))
    s = Shape(features, shape)
    return Fix2(unflatten, s), s
end

