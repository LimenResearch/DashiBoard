# Dense structure

# TODO: support passing custom initializers
struct DenseSpec{L, S}
    layer::L
    size::Maybe{Int}
    sigma::S
end

requires_format(::DenseSpec, ::AbstractFormat) = FlatFormat()

function instantiate(
        d::DenseSpec, inputsize::Dims, inputformat::AbstractFormat;
        outputsize::Maybe{Dims} = nothing, outputformat::Maybe{AbstractFormat} = nothing
    )

    ch_in = only(inputsize)

    # TODO: better error message if this fails
    ch_out = @something d.size only(outputsize)

    layer = isnothing(d.sigma) ? d.layer(ch_in => ch_out) : d.layer(ch_in => ch_out, d.sigma)

    return layer, (ch_out,), inputformat
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

function requires_format(::ConvSpec{<:Any, <:Any, N}, ::AbstractFormat) where {N}
    return SpatialFormat{N}()
end

function instantiate(
        c::ConvSpec, inputsize::Dims, inputformat::AbstractFormat;
        outputsize::Maybe{Dims} = nothing, outputformat::Maybe{AbstractFormat} = nothing
    )

    ch_in = last(inputsize)
    ch_out = @something c.size last(outputsize)
    layer = c.layer(c.kernel, ch_in => ch_out, c.sigma; c.pad, c.stride, c.dilation)
    return layer, get_outputsize(layer, inputsize), inputformat
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
