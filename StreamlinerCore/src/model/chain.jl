function push_layer!(layers, l, input::Shape, output::Shape)
    layer, sh = instantiate(l, input, output)
    push!(layers, layer)
    return sh
end

function concat_layers(ls::AbstractVector, input::Shape, output::Shape)

    layers, sh = [], input
    shapes = map(requires_shape, ls)

    for i in eachindex(ls)
        l, sh′, sh′′ = ls[i], shapes[i], get(shapes, i + 1, output)
        if sh′.format !== sh.format
            # Try and make data compatible with `ls[i]`
            sh = push_layer!(layers, formatter, sh, sh′)
        end
        # Try and make data compatible with `ls[i+1]` or `output`
        sh = push_layer!(layers, l, sh, sh′′)
    end

    if !isnothing(output)
        # output reformatting
        if output.format !== sh.format
            sh = push_layer!(layers, formatter, sh, output)
        end

        if !isnothing(output.features) && output.features != sh.features
            msg = """
            Mismatching number of output features: found $(sh.features), expected $(output.features).
            """
            throw(ArgumentError(msg))
        end

        # output resampling
        if !isnothing(output.shape)
            if !(sh.format isa ClassicalFormat) && output.shape != sh.shape
                throw(ArgumentError("Automatic shape adjustment is only supported for classical format"))
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

function chain(ls::AbstractVector, input::Shape, output::Shape)
    layers, sh = concat_layers(ls, input, output)
    # Convert to `Tuple` to improve runtime performance at the cost of compilation
    return Flux.Chain(Tuple(layers)), sh
end
