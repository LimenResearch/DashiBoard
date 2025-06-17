# Set computation utils

_union!(s::AbstractSet{<:AbstractString}, x::AbstractString) = push!(s, x)
_union!(s::AbstractSet{<:AbstractString}, x::AbstractVector) = union!(s, x)
_union!(s::AbstractSet{<:AbstractString}, ::Nothing) = s

stringset!(s::AbstractSet{<:AbstractString}, args...) = (foreach(Fix1(_union!, s), args); s)

stringset(args...) = stringset!(OrderedSet{String}(), args...)

# Dict conversion

to_string_dict(d) = constructfrom(Dict{String, Any}, d)

to_symbol_dict(d) = constructfrom(Dict{Symbol, Any}, d)

# Option computation and widget helpers

const METHOD_OPTIONS_REGEX = r"^method_options\.\d+\.(.*)$"
const MODEL_OPTIONS_REGEX = r"^model_options\.\d+\.(.*)$"
const TRAINING_OPTIONS_REGEX = r"^training_options\.\d+\.(.*)$"

function extract_options(c::AbstractDict, r::Regex)
    d = Dict{String, Any}()
    for (k, v) in pairs(c)
        m = match(r, k)
        isnothing(m) || (d[only(m)] = v)
    end
    return d
end

function extract_options(c::AbstractDict, key::AbstractString, r::Regex)
    return get(c, key) do
        extract_options(c, r)
    end
end

function generate_widget(
        conf::AbstractDict,
        type::AbstractString,
        name::AbstractString,
        idx::Integer
    )

    key = string(type, "_", "options", ".", idx, ".", conf["key"])
    visible = Dict(type => [name])
    return Widget(key, conf; visible)
end

# Card computation utils

filter_partition(partition::AbstractString, n::Integer = 1) = Where(Get(partition) .== n)

function filter_partition(::Nothing, n::Integer = 1)
    if n != 1
        throw(ArgumentError("Data has not been split"))
    end
    return identity
end

function check_order(c::AbstractDict)
    order_by = get(c, "order_by", String[])
    if isempty(order_by)
        throw(
            ArgumentError(
                """
                At least one sorter is required.
                """
            )
        )
    end
    return true
end

# Prediction utils

_predict(m::RegressionModel, X::AbstractMatrix) = predict(m, X)

_predict(m::MDS, X::AbstractMatrix) = stack(Fix1(vec ∘ predict, m), eachcol(X))
