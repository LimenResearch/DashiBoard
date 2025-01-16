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

function Shape{N}() where {N}
    format = N === 0 ? FlatFormat() : SpatialFormat{N}()
    return Shape(format)
end

Shape(format::AbstractFormat) = Shape(format, nothing, nothing)

function Shape(shape::NTuple{N, Integer}, features::Integer) where {N}
    (; format) = Shape{N}()
    return Shape(format, shape, features)
end

Shape(features::Integer) = Shape((), features)

Shape(template::Template) = Shape(front(template.size), last(template.size))

function get_outputshape(layer, sh::Shape)
    size = sh.shape..., sh.features
    shape..., features, _ = Flux.outputsize(layer, size, padbatch = true)
    return Shape(shape, features)
end
