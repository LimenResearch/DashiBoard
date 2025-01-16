function push_layer!(layers, l, input::Shape, output::Maybe{Shape} = nothing)
    layer, sh = instantiate(l, input, output)
    push!(layers, layer)
    return sh
end

function concat_layers(ls::AbstractVector, input::Shape, output::Maybe{Shape})

    layers, sh = [], input

    for i in eachindex(ls)
        l = ls[i]
        sh′ = requires_shape(l, sh)
        if sh′.format !== sh.format
            sh = push_layer!(layers, formatter, sh, sh′)
        end
        # TODO: smarter method to also pass info about following layer?
        sh′ = i == lastindex(ls) ? output : nothing
        sh = push_layer!(layers, l, sh, sh′)
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
                l = meanpool(; window)
                sh = push_layer!(layers, l, sh)
            end
            if sh.shape != output.shape
                l = upsample(size = output.shape)
                sh = push_layer!(layers, l, sh)
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
