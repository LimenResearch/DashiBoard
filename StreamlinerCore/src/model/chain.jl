function push_layer!(layers, l, input::Shape, output::Maybe{Shape})
    layer, sh = instantiate(l, input, output)
    push!(layers, layer)
    return sh
end

function concat_layers(ls::AbstractVector, input::Shape, output::Maybe{Shape})

    layers, sh = [], input
    sh′ = requires_shape(first(ls))

    for i in eachindex(ls)
        if sh′.format !== sh.format
            sh = push_layer!(layers, formatter, sh, sh′)
        end
        sh′ = i == lastindex(ls) ? output : requires_shape(ls[i + 1])
        sh = push_layer!(layers, ls[i], sh, sh′)
    end

    if !isnothing(output)
        # output reformatting
        if output.format !== sh.format
            sh = push_layer!(layers, formatter, sh, output)
        end

        # output resampling
        if !isnothing(output.shape)
            if !(sh.format isa ClassicalFormat)
                throw(ArgumentError("Only classical format is allowed as chain output"))
            end
            window = map(div, sh.shape, output.shape)
            if any(>(1), window)
                l = meanpool(; window = max.(window, 1))
                sh = push_layer!(layers, l, sh, output)
            end
            if sh.shape != output.shape
                l = upsample(size = output.shape)
                sh = push_layer!(layers, l, sh, output)
            end
        end
    end

    return layers, sh
end

# TODO: support empty chain?
function chain(ls::AbstractVector, input::Shape, output::Maybe{Shape} = nothing)
    layers, sh = concat_layers(ls, input, output)
    # Convert to `Tuple` to improve runtime performance at the cost of compilation
    return Flux.Chain(Tuple(layers)), sh
end
