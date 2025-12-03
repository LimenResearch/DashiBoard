## Format

abstract type AbstractFormat{N} end

abstract type ClassicalFormat{N} <: AbstractFormat{N} end

struct SpatialFormat{N} <: ClassicalFormat{N}
    function SpatialFormat{N}() where {N}
        if N ≤ 0
            msg = "`N` must be at least `1` in a `SpatialFormat`."
            throw(ArgumentError(msg))
        end
        return new{N}()
    end
end

struct FlatFormat <: ClassicalFormat{0} end

ClassicalFormat{N}() where {N} = N === 0 ? FlatFormat() : SpatialFormat{N}()

function requires_format end

## Shape

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
    format = ClassicalFormat{N}()
    return Shape(format, shape, features)
end

Shape(template::Template) = Shape(front(template.size), last(template.size))

function get_outputshape(layer, sh::Shape)
    size = sh.shape..., sh.features
    shape..., features, _ = Flux.outputsize(layer, size, padbatch = true)
    return Shape(shape, features)
end

function infer_features(sh::Shape, sp)
    if !isnothing(sp.features)
        return sp.features
    elseif !isnothing(sh.features) && sh.format === requires_shape(sp).format
        return sh.features
    else
        throw(ArgumentError("Could not infer output features."))
    end
end

requires_shape(x) = Shape(requires_format(x))
