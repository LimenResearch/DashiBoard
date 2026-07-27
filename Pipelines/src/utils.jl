# General utils

_map!(f::F, d::AbstractDict) where {F} = (map!(f, values(d)); d)
_map!(f::F, v::AbstractVector) where {F} = map!(f, v, v)

map_into(f::F, ::Type{T}, x) where {F, T} = _map!(f, T(x))::T

get_indices(d::AbstractDict{<:Any, I}, ks::AbstractVector) where {I} = I[d[k] for k in ks]

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
