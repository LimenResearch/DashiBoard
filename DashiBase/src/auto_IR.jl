to_nt(ir::I) where {I <: AbstractIR} = NamedTuple{fieldnames(I)}(ntuple(Fix1(getfield, ir), fieldcount(I)))

find_value(x1, x2) = something(x2, x1, Some(nothing))

function merge_IR(i1::AbstractIR, i2::I) where {I <: AbstractIR}
    # Discard inferred version in case of `ReferenceIR`
    return if i1 isa TrivialIR || i2 isa ReferenceIR
        i2
    elseif i2 isa TrivialIR
        i1
    else
        nt1, nt2 = to_nt(i1), to_nt(i2)
        StructUtils.make(I, map(find_value, nt1, nt2))
    end
end

# generic IR utils

_eltype(::Type{V}) where {V <: Maybe{AbstractVector}} = Any
_eltype(::Type{V}) where {V <: Maybe{AbstractVector{T}}} where {T} = T

function IR_from_type(T::Type, _default)::AbstractIR
    if T <: Nothing
        throw(ArgumentError("Type `Nothing` not supported, did you mean `Union{T, Nothing}`?"))
    end

    default = StructUtils.lower(DashiStyle(), _default)

    # we consider nullable types, which correspond to optional fields with no default
    return (T <: Maybe{Integer}) ? IntegerIR(; default) :
        (T <: Maybe{Number}) ? NumberIR(; default) :
        (T <: Maybe{AbstractString}) ? StringIR(; default) :
        (T <: Maybe{Symbol}) ? StringIR(; default) :
        (T <: Maybe{Enum}) ? StringIR(; default, enum = enum_instances(T)) :
        (T <: Maybe{AbstractVector}) ? ArrayIR{_eltype(T)}(; default) :
        TrivialIR()
end

# schema for composite structures

function auto_property(
        ::Type{T}, (key, config)::Pair{<:AbstractString, <:Maybe{AbstractIR}};
        default = nothing
    ) where {T}
    value = merge_IR(IR_from_type(T, default), something(config, TrivialIR()))
    is_required = isnothing(default) && !(Nothing <: T)
    return Property(key => value; required = is_required)
end

function ObjectIR(::Type{T}) where {T}
    tags = fieldtags(DashiStyle(), T)
    defaults = fielddefaults(DashiStyle(), T)
    properties::Vector{Property} = map(collect(fieldnames(T)), collect(fieldtypes(T))) do field, S
        config = get_dashi(get(tags, field, nothing))
        default = get(defaults, field, nothing)
        auto_property(S, string(field) => config; default)
    end
    return ObjectIR(; properties)
end
