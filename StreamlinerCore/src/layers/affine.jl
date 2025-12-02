# Dense structure

# TODO: support passing custom initializers
struct DenseSpec{L, S}
    layer::L
    features::Maybe{Int}
    sigma::S
end

requires_format(::DenseSpec) = FlatFormat()

function instantiate(d::DenseSpec, input::Shape, output::Shape)
    f_in = input.features
    f_out = infer_features(output, d)
    layer = isnothing(d.sigma) ? d.layer(f_in => f_out) : d.layer(f_in => f_out, d.sigma)
    return layer, Shape(f_out)
end

# Conv structure

struct ConvSpec{N, N′, L, S}
    layer::L
    features::Maybe{Int}
    sigma::S
    kernel::NTuple{N, Int}
    pad::NTuple{N′, Int}
    stride::NTuple{N, Int}
    dilation::NTuple{N, Int}
end

function ConvSpec(layer, kernel, features, sigma; pad = 0, stride = 1, dilation = 1)

    kernel, pad, stride, dilation =
        Tuple(kernel), tuplify_list(pad), tuplify_list(stride), tuplify_list(dilation)

    N = length(kernel)

    pad′ = expand(2N, pad)
    stride′ = expand(N, stride)
    dilation′ = expand(N, dilation)

    return ConvSpec(layer, features, sigma, kernel, pad′, stride′, dilation′)
end

requires_format(::ConvSpec{N}) where {N} = SpatialFormat{N}()

function instantiate(c::ConvSpec, input::Shape, output::Shape)
    ch_in = input.features
    ch_out = infer_features(output, c)
    layer = c.layer(c.kernel, ch_in => ch_out, c.sigma; c.pad, c.stride, c.dilation)
    return layer, get_outputshape(layer, input)
end

# Dense-like

dense(; features = nothing, sigma = "") = DenseSpec(Dense, features, PARSER[].sigmas[sigma])

rnn(; features = nothing, sigma = "tanh") = DenseSpec(RNN, features, PARSER[].sigmas[sigma])

lstm(; features = nothing) = DenseSpec(LSTM, features, nothing)

gru(; features = nothing) = DenseSpec(GRU, features, nothing)

# Conv-like

conv(; kernel, features = nothing, sigma = "", ks...) =
    ConvSpec(Conv, kernel, features, PARSER[].sigmas[sigma]; ks...)

conv_t(; kernel, features = nothing, sigma = "", ks...) =
    ConvSpec(ConvTranspose, kernel, features, PARSER[].sigmas[sigma]; ks...)
