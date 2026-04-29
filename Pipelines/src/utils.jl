# General utils

to_stringlist(s::Union{AbstractString, Nothing}) = isnothing(s) ? String[] : String[s]

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
