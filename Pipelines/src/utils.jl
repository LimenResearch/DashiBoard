# String list utils

to_stringlist(s::Union{AbstractString, Nothing}) = isnothing(s) ? String[] : String[s]

# Card computation utils

select_columns(args...) = Select(args = Get.(union(args...)))

sort_columns(cols::AbstractVector) = Order(by = Get.(cols))

filter_partition(partition::AbstractString, n::Integer = 1) = Where(Get(partition) .== n)

function filter_partition(::Nothing, n::Integer = 1)
    if n != 1
        throw(ArgumentError("Data has not been split"))
    end
    return identity
end

# Prediction utils

_predict(m::RegressionModel, X::AbstractMatrix) = predict(m, X)

_predict(m::MDS, X::AbstractMatrix) = stack(Fix1(vec ∘ predict, m), eachcol(X))

# Configuration utils

function get_params(m)
    return Any[getproperty(m, k) for k in propertynames(m)]
end

function get_options(m)
    return StringDict(string(k) => getproperty(m, k) for k in propertynames(m))
end
