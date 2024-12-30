# Dense structure

# TODO: support passing custom initializers
struct DenseSpec{L, S}
    layer::L
    size::Int
    sigma::S
end

requires_format(::DenseSpec, ::AbstractDataFormat) = FlatFormat()

function instantiate(d::DenseSpec, size, fmt)
    i = only(size)
    layer = isnothing(d.sigma) ? d.layer(i => d.size) : d.layer(i => d.size, d.sigma)

    return layer, (d.size,), fmt
end

# Conv structure

struct ConvSpec{L, S, N, N′}
    layer::L
    size::Int
    sigma::S
    kernel::NTuple{N, Int}
    pad::NTuple{N′, Int}
    stride::NTuple{N, Int}
    dilation::NTuple{N, Int}
end

function ConvSpec(layer, kernel, size, sigma; pad = 0, stride = 1, dilation = 1)

    kernel, pad, stride, dilation =
        Tuple(kernel), tuplify_list(pad), tuplify_list(stride), tuplify_list(dilation)

    N = length(kernel)

    pad′ = expand(2N, pad)
    stride′ = expand(N, stride)
    dilation′ = expand(N, dilation)

    return ConvSpec(layer, size, sigma, kernel, pad′, stride′, dilation′)
end

function requires_format(::ConvSpec{<:Any, <:Any, N}, ::AbstractDataFormat) where {N}
    return SpatialFormat{N}()
end

function instantiate(c::ConvSpec, size, fmt)
    N = length(c.kernel)
    i = last(size)
    layer = c.layer(c.kernel, i => c.size, c.sigma; c.pad, c.stride, c.dilation)
    outputsize = get_outputsize(layer, size)
    return layer, outputsize, fmt
end

# Dense-like

dense(; size, sigma = "") = DenseSpec(Dense, size, PARSER[].sigmas[sigma])

rnn(; size, sigma = "tanh") = DenseSpec(RNN, size, PARSER[].sigmas[sigma])

lstm(; size) = DenseSpec(LSTM, size, nothing)

gru(; size) = DenseSpec(GRU, size, nothing)

# Conv-like

conv(; kernel, size, sigma = "", ks...) =
    ConvSpec(Conv, kernel, size, PARSER[].sigmas[sigma]; ks...)

conv_t(; kernel, size, sigma = "", ks...) =
    ConvSpec(ConvTranspose, kernel, size, PARSER[].sigmas[sigma]; ks...)
