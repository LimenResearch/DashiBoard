# Simple layers with no weights

struct BySlice{N, L, D}
    layer::L
    dims::D
    BySlice{N}(layer::L, dims::D) where {N, L, D} = new{N, L, D}(layer, dims)
end

(b::BySlice)(x) = b.layer(x; b.dims)

requires_format(::BySlice{N}) where {N} = ClassicalFormat{N}()

instantiate(b::BySlice, input::Shape, ::Shape) = b, input

# Parameter-free

softmax(; N = 0, dims = N + 1) = BySlice{N}(Flux.softmax, dims)

logsoftmax(; N = 0, dims = N + 1) = BySlice{N}(Flux.logsoftmax, dims)

logsumexp(; N = 0, dims = N + 1) = BySlice{N}(Flux.logsumexp, dims)
