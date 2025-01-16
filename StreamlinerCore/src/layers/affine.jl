# Dense structure

# TODO: support passing custom initializers
struct DenseSpec{L, S}
    layer::L
    features::Maybe{Int}
    sigma::S
end

requires_shape(::DenseSpec) = Shape(FlatFormat())

function instantiate(d::DenseSpec, input::Shape, output::Maybe{Shape})
    f_in = input.features
    f_out = if !isnothing(d.features)
        d.features
    else
        if isnothing(output) || output.format !== requires_shape(d).format
            throw(ArgumentError("Could not infer output size"))
        end
        output.features
    end
    layer = isnothing(d.sigma) ? d.layer(f_in => f_out) : d.layer(f_in => f_out, d.sigma)
    return layer, Shape(f_out)
end

# Conv structure

struct ConvSpec{L, S, N, N′}
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

function requires_shape(::ConvSpec{<:Any, <:Any, N}) where {N}
    return Shape(SpatialFormat{N}())
end

function instantiate(c::ConvSpec, input::Shape, output::Maybe{Shape})
    ch_in = input.features
    ch_out = if !isnothing(c.features)
        c.features
    else
        if isnothing(output) || output.format !== requires_shape(c).format
            throw(ArgumentError("Could not infer output size"))
        end
        output.features
    end
    ch_out = @something c.features output.features
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
