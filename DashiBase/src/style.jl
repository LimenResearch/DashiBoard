struct DashiStyle <: StructUtils.StructStyle end

get_dashi(s::Maybe{NamedTuple}) = isnothing(s) ? nothing : get(s, :dashi, nothing)

construct(::Type{T}, x) where {T} = StructUtils.make(T, x, DashiStyle())

function to_config(x)
    config = StringDict()
    StructUtils.make!(DashiStyle(), config, x)
    return config
end

function StructUtils.lift(::DashiStyle, ::Type{String}, x::AbstractVector, tags)
    if get_dashi(tags) != VARIABLE_DEF
        msg = """
        Automatic vector to string conversion is only allowed for fields
        with schema `$(VARIABLE_DEF)`.
        """
        throw(ArgumentError(msg))
    elseif length(x) != 1
        msg = """
        Automatic vector to string conversion is only allowed for vector
        of length `1`, found `length = $(length(x))`.
        """
        throw(ArgumentError(msg))
    else
        s::String = only(x)
        return s, nothing
    end
end

StructUtils.lower(::DashiStyle, x::Symbol) = string(x)

StructUtils.lower(::DashiStyle, x::Enum) = string(Symbol(x))

_instances(::Type{T}) where {T <: Enum} = instances(T)
_instances(::Type{Maybe{T}}) where {T <: Enum} = instances(T)

enum_instances(T::Type) = String[StructUtils.lower(DashiStyle(), x) for x in _instances(T)]
