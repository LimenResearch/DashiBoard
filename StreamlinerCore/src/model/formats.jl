abstract type AbstractFormat{N} end

abstract type ClassicalFormat{N} <: AbstractFormat{N} end

struct SpatialFormat{N} <: ClassicalFormat{N}
    function SpatialFormat{N}() where {N}
        if N ≤ 0
            throw(
                ArgumentError(
                    """
                    `N` must be at least `1` in a `SpatialFormat`.
                    """
                )
            )
        end
        return new{N}()
    end
end

struct FlatFormat <: ClassicalFormat{0} end

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
    return Shape(Shape{N}().format, shape, features)
end

Shape(features::Integer) = Shape(FlatFormat(), (), features)

Shape{N}() where {N} = N === 0 ? Shape(FlatFormat()) : Shape(SpatialFormat{N}())

Shape(template::Template) = Shape(front(template.size), last(template.size))

function get_outputshape(layer, sh::Shape)
    size = sh.shape..., sh.features
    shape..., features, _ = Flux.outputsize(layer, size, padbatch = true)
    return Shape(shape, features)
end

struct Formatter end

const formatter = Formatter()

function instantiate(::Formatter, input::Shape, output::Shape)
    return reformat(input.format, output.format, input, output)
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
    sh = Shape(shape, features)
    return Fix2(unflatten, sh), sh
end
