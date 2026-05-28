# General utils

to_stringlist(s::Union{AbstractString, Nothing}) = isnothing(s) ? String[] : String[s]

get_options(m) = StringDict(string(k) => getproperty(m, k) for k in propertynames(m))

# JSON schema utils

function json_integer(;
        min::Union{Integer, Nothing} = nothing,
        max::Union{Integer, Nothing} = nothing
    )
    sch = Dict{String, Any}("type" => "integer")
    isnothing(min) || (sch["minimum"] = min)
    isnothing(max) || (sch["maximum"] = max)
    return sch
end

function json_string(; min::Integer = 0)
    return Dict("type" => "string", "minLength" => min)
end

function json_var(vars)
    enum::Vector{String} = collect(String, vars)
    return json_var(enum)
end

function json_var(vars::AbstractVector{<:AbstractString})
    return Dict("type" => "string", "enum" => vars)
end

function json_vars(vars; min::Integer = 0)
    return Dict(
        "type" => "array",
        "items" => json_var(vars),
        "minItems" => min
    )
end

nullable(s) = Dict("anyOf" => [s, Dict("type" => "null")])

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
