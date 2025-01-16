# Dense structure

# TODO: support passing custom initializers
struct DenseSpec{L, S}
    layer::L
    size::Maybe{Int}
    sigma::S
end

requires_shape(::DenseSpec, ::Shape) = Shape(FlatFormat())

function instantiate(d::DenseSpec, input::Shape, output::Maybe{Shape})

    f_in = input.features

    # TODO: better error message if this fails
    f_out = @something d.size output.features

    layer = isnothing(d.sigma) ? d.layer(f_in => f_out) : d.layer(f_in => f_out, d.sigma)

    return layer, Shape(f_out)
end

# Conv structure

struct ConvSpec{L, S, N, N′}
    layer::L
    size::Maybe{Int}
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

function requires_shape(::ConvSpec{<:Any, <:Any, N}, ::Shape) where {N}
    return Shape(SpatialFormat{N}())
end

function instantiate(c::ConvSpec, input::Shape, output::Maybe{Shape})
    ch_in = input.features
    ch_out = @something c.size output.features
    layer = c.layer(c.kernel, ch_in => ch_out, c.sigma; c.pad, c.stride, c.dilation)
    return layer, get_outputshape(layer, input)
end

# Dense-like

dense(; size = nothing, sigma = "") = DenseSpec(Dense, size, PARSER[].sigmas[sigma])

rnn(; size = nothing, sigma = "tanh") = DenseSpec(RNN, size, PARSER[].sigmas[sigma])

lstm(; size = nothing) = DenseSpec(LSTM, size, nothing)

gru(; size = nothing) = DenseSpec(GRU, size, nothing)

# Conv-like

conv(; kernel, size = nothing, sigma = "", ks...) =
    ConvSpec(Conv, kernel, size, PARSER[].sigmas[sigma]; ks...)

conv_t(; kernel, size = nothing, sigma = "", ks...) =
    ConvSpec(ConvTranspose, kernel, size, PARSER[].sigmas[sigma]; ks...)
