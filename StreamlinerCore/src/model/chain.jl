function push_layer!(
        layers, l, inputsize::Dims, inputformat::AbstractFormat;
        outputsize::Maybe{Dims} = nothing, outputformat::Maybe{AbstractFormat} = nothing
    )

    layer, size, format = instantiate(l, inputsize, inputformat; outputsize, outputformat)
    push!(layers, layer)
    return size, format
end

function concat_layers(
        ls, inputsize::Dims, inputformat::Maybe{AbstractFormat} = nothing;
        outputsize::Maybe{Dims} = nothing,
        outputformat::Maybe{AbstractFormat} = nothing
    )

    inputformat = @something inputformat defaultformat(inputsize)
    isnothing(outputsize) || (outputformat = @something outputformat defaultformat(outputsize))

    layers, size, format = [], inputsize, inputformat

    for l in ls
        format′ = requires_format(l, format)
        size, format = push_layer!(layers, Reshaper(format′), size, format)
        size, format = push_layer!(layers, l, size, format)
    end

    # output reshaper
    l = Reshaper(something(outputformat, format))
    size, format = push_layer!(layers, l, size, format)

    # output resizer
    if !isnothing(outputsize)
        if !(format isa SpatialFormat)
            throw(ArgumentError("Only spatial format is allowed as chain output"))
        end
        window = map(div, front(size), front(outputsize))
        if any(>(1), window)
            l = meanpool(; window)
            size, format = push_layer!(layers, l, size, format)
        end
        if front(size) != front(outputsize)
            l = upsample(size = front(outputsize))
            size, format = push_layer!(layers, l, size, format)
        end
    end

    # Some reshaping layers might be trivial
    filter!(!isnothing, layers)

    return layers, size, format
end

# TODO: support empty chain?
function chain(args...; params...)
    layers, size, format = concat_layers(args...; params...)
    # Convert to `Tuple` to improve runtime performance at the cost of compilation
    return Flux.Chain(Tuple(layers)), size, format
end
