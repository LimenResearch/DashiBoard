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
    return flatten, Shape((), features)
end

# TODO: attempt to match output shape
function reformat(::FlatFormat, ::SpatialFormat{N}, input::Shape, output::Shape) where {N}
    factors = factor(Vector, input.features)
    shape = ntuple(n -> get(factors, n, 1), N)
    features = div(input.features, prod(shape))
    sh = Shape(shape, features)
    return Fix2(unflatten, sh), sh
end
