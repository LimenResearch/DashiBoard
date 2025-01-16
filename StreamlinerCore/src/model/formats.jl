abstract type AbstractFormat{N} end

abstract type ClassicalFormat{N} <: AbstractFormat{N} end

struct SpatialFormat{N} <:ClassicalFormat{N} end

struct FlatFormat <:ClassicalFormat{0} end

struct Shape{N, T <: AbstractFormat{N}}
    format::T
    shape::Maybe{Dims{N}}
    features::Maybe{Int}

    function Shape(
            format::AbstractFormat{N},
            shape::Maybe{NTuple{N, Integer}},
            features::Maybe{Integer},
        ) where {N}

        T = typeof(format)
        return new{N, T}(format, shape, features)
    end
end

Shape(format::AbstractFormat) = Shape(format, nothing, nothing)

function Shape(shape::NTuple{N, Integer}, features::Integer) where {N}
    format = SpatialFormat{N}()
    return Shape(format, shape, features)
end

Shape(features::Integer) = Shape(FlatFormat(), (), features)

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
    s = Shape(shape, features)
    return Fix2(unflatten, s), s
end

