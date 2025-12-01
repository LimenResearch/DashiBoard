struct RangeSelector
    first::Union{Int, Nothing}
    last::Union{Int, Nothing}
    min::Union{Int, Nothing}
    max::Union{Int, Nothing}
end

function range_selector(;
        first::Maybe{Integer} = nothing,
        last::Maybe{Integer} = nothing,
        min::Maybe{Integer} = nothing,
        max::Maybe{Integer} = nothing
    )
    return RangeSelector(first, last, min, max)
end

range_selector(d::AbstractDict) = range_selector(; make(SymbolDict, d)...)

to_range(n::Integer, sel::RangeSelector) = to_range(Base.OneTo(n), sel)

function to_range(ax::AbstractUnitRange, sel::RangeSelector)
    i0, i1 = firstindex(ax), lastindex(ax)
    (; first, last, min, max) = sel
    return if !isnothing(last)
        ax[(i1 - last + 1):i1]
    elseif !isnothing(first)
        ax[i0:(i0 + first - 1)]
    else
        min = something(min, i0)
        max = something(max, i1)
        ax[min:max]
    end
end

struct Selector{N}
    window::NTuple{N, RangeSelector}
end

function (s::Selector)(x::AbstractArray)
    shape..., _, _ = axes(x)
    I = map(to_range, shape, s.window)
    return x[I...]
end

requires_shape(::Selector{N}) where {N} = SpatialFormat{N}()

function instantiate(s::Selector, input::Shape, ::Shape)
    shape = @. length(to_range(input.shape, s.window))
    return s, Shape(shape, input.features)
end

(s::Selector)(size, fmt) = Fix1(forward, s), map(length, to_ranges(size, s.window)), fmt

function selector(; window)
    w::Vector{RangeSelector} = range_selector.(window)
    return Selector(Tuple(w))
end
