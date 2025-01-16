# Simple layers with no weights

struct BySlice{L, D}
    layer::L
    dims::D
end

(b::BySlice)(x) = b.layer(x; b.dims)

requires_format(::BySlice, ::AbstractFormat{N}) where {N} = SpatialFormat{N}()

instantiate(b::BySlice, size, fmt; outputsize = nothing, outputformat = nothing) = b, size, fmt

# Parameter-free

softmax(; dims = 1) = BySlice(Flux.softmax, dims)

logsoftmax(; dims = 1) = BySlice(Flux.logsoftmax, dims)

logsumexp(; dims = 1) = BySlice(Flux.logsumexp, dims)
