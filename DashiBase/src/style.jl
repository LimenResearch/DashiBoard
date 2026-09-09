struct DashiStyle <: StructUtils.StructStyle end

get_dashi(s::Maybe{NamedTuple}) = isnothing(s) ? nothing : get(s, :dashi, nothing)

construct(::Type{T}, x) where {T} = StructUtils.make(T, x, DashiStyle())

function to_config(x)
    config = StringDict()
    StructUtils.make!(DashiStyle(), config, x)
    return config
end

StructUtils.lower(::DashiStyle, x::Symbol) = string(x)

StructUtils.lower(::DashiStyle, x::Enum) = string(Symbol(x))

_instances(::Type{T}) where {T <: Enum} = instances(T)
_instances(::Type{Maybe{T}}) where {T <: Enum} = instances(T)

enum_instances(T::Type) = String[StructUtils.lower(DashiStyle(), x) for x in _instances(T)]
