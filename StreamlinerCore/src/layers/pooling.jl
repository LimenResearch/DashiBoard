# Pooling structure

struct PoolSpec{N, N′, L}
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

requires_format(::PoolSpec{N}) where {N} = ClassicalFormat{N}()

function instantiate(p::PoolSpec, input::Shape, ::Shape)
    layer = p.layer(p.window; p.pad, p.stride)
    return layer, get_outputshape(layer, input)
end

# Upsampling structure

struct Upsample{N, L}
    layer::L
    size::NTuple{N, Int}
    align_corners::Bool
end

(u::Upsample)(x) = u.layer(x; u.size, u.align_corners)

requires_format(::Upsample{N}) where {N} = ClassicalFormat{N}()

function instantiate(u::Upsample, input::Shape, ::Shape)
    return u, Shape(input.format, u.size, input.features)
end

# Functions

maxpool(; window, ks...) = PoolSpec(MaxPool, window; ks...)

meanpool(; window, ks...) = PoolSpec(MeanPool, window; ks...)

const UPSAMPLERS = (linear = upsample_linear, nearest = upsample_nearest)

function upsample(; type = "linear", size, align_corners::Bool = false)
    upsampler = UPSAMPLERS[Symbol(type)]
    return Upsample(upsampler, Tuple(size), align_corners)
end
