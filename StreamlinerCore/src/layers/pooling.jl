# Pooling structure

struct PoolSpec{L, N, N′}
    layer::L
    window::NTuple{N, Int}
    pad::NTuple{N′, Int}
    stride::NTuple{N, Int}
end

function PoolSpec(layer, window; pad = 0, stride = window)

    window, pad, stride =
        Tuple(window), tuplify_list(pad), tuplify_list(stride)

    N = length(window)

    pad′ = expand(2N, pad)
    stride′ = expand(N, stride)

    return PoolSpec(layer, window, pad′, stride′)
end

requires_format(::PoolSpec{<:Any, N}, ::AbstractDataFormat) where {N} = SpatialFormat{N}()

function instantiate(p::PoolSpec, size, fmt)
    layer = p.layer(p.window; p.pad, p.stride)
    outputsize = get_outputsize(layer, size)
    return layer, outputsize, fmt
end

# Upsampling structure

struct Upsample{L, N}
    layer::L
    size::NTuple{N, Int}
    align_corners::Bool
end

(u::Upsample)(x) = u.layer(x; u.size, u.align_corners)

function requires_format(::Upsample{<:Any, N}, ::AbstractDataFormat) where {N}
    return SpatialFormat{N}()
end

instantiate(u::Upsample, (_..., feats), fmt) = u, (u.size..., feats), fmt

# Functions

maxpool(; window, ks...) = PoolSpec(MaxPool, window; ks...)

meanpool(; window, ks...) = PoolSpec(MeanPool, window; ks...)

const UPSAMPLERS = (linear = upsample_linear, nearest = upsample_nearest)

function upsample(; type = "linear", size, align_corners::Bool = false)
    upsampler = UPSAMPLERS[Symbol(type)]
    return Upsample(upsampler, Tuple(size), align_corners)
end
