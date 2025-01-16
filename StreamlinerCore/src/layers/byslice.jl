# Simple layers with no weights

struct BySlice{L, D}
    layer::L
    dims::D
end

(b::BySlice)(x) = b.layer(x; b.dims)

requires_shape(::BySlice, ::Shape{N}) where {N} = Shape{N}()

instantiate(b::BySlice, input::Shape, ::Maybe{Shape}) = b, input

# Parameter-free

softmax(; dims = 1) = BySlice(Flux.softmax, dims)

logsoftmax(; dims = 1) = BySlice(Flux.logsoftmax, dims)

logsumexp(; dims = 1) = BySlice(Flux.logsumexp, dims)
