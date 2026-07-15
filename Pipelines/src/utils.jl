# Inner constructor utils

has_keywords(xs::AbstractVector) = @capture :(f($(xs...))) f(args__; kwargs__)

macro optional_type_params(ex)
    ismatch = @capture(
        ex, function f_{Ps__}(xs__) where {Ts__}
            body_
        end
    )

    if !ismatch || isempty(Ps) || has_keywords(xs)
        msg =
        """
        Expected expression of the type
        ```
        function f{Ps...}(xs...) where {Ts...}
            body
        end
        ```
        with at least one `P` and no keyword arguments.
        """
        throw(ArgumentError(msg))
    end

    return quote
        function $f{$(Ps...)}($(xs...)) where {$(Ts...)}
            $body
        end

        $f($(xs...)) where {$(Ts...)} = $f{$(Ps...)}($(xs...))
    end |> esc
end

# General utils

to_stringlist(s::Union{AbstractString, Nothing}) = isnothing(s) ? String[] : String[s]
to_stringlist(s::AbstractVector) = convert(Vector{String}, s)

function to_maybestring(s::AbstractVector)::Union{String, Nothing}
    return isempty(s) ? nothing : only(s)
end

to_maybestring(s::Union{AbstractString, Nothing})::Union{String, Nothing} = s

# Card computation utils

select_columns(args...) = Select(args = Get.(union(args...)))

sort_columns(cols::AbstractVector) = Order(by = Get.(cols))

filter_training(partition::AbstractString) = Where(Get(partition) .== 1)
filter_training(::Nothing) = Where(Lit(true)) # without partition, everything goes in training

# Prediction utils

_predict(m::RegressionModel, X::AbstractMatrix) = predict(m, X)

_predict(m::MDS, X::AbstractMatrix) = stack(Fix1(vec ∘ predict, m), eachcol(X))

# Multithreading utils

putmany!(ch::Channel, iter) = foreach(Fix1(put!, ch), iter)

function to_channel(iter)
    n = length(iter)
    T = eltype(iter)
    return Channel{T}(ch -> putmany!(ch, iter), n, spawn = true)
end
