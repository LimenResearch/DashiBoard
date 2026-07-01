# General utils

to_stringlist(s::Union{AbstractString, Nothing}) = isnothing(s) ? String[] : String[s]
to_stringlist(s::AbstractVector) = convert(Vector{String}, s)

function to_maybestring(s::AbstractVector)::Union{String, Nothing}
    return isempty(s) ? nothing : only(s)
end

to_maybestring(s::Union{AbstractString, Nothing})::Union{String, Nothing} = s

get_options(m) = StringDict(string(k) => getproperty(m, k) for k in propertynames(m))

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

# Card creation utils

# Experimental adjustment configuration
function adjust_config(::Type{C}, d::AbstractDict) where {C}
    types = Dict{String, String}()
    for (field, T) in zip(fieldnames(C), fieldtypes(C))
        types[string(field)] =
            (T <: Union{AbstractString, Nothing}) ? "maybestring" :
            (T <: AbstractVector) ? "list" : "any"
    end
    d1 = Dict{String, Any}()
    for (k, v) in d
        type = get(types, k, nothing)
        d1[k] = if (v isa AbstractVector) && (type == "maybestring")
            to_maybestring(v)
        elseif (v isa Union{AbstractString, Nothing}) && (type == "list")
            to_stringlist(v)
        else
            v
        end
    end
    return d1
end
