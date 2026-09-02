to_nt(ir::I) where {I <: AbstractIR} = NamedTuple{fieldnames(I)}(ntuple(Base.Fix1(getfield, ir), fieldcount(I)))

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

function IR_from_type(T::Type, _default)::AbstractIR
    if T <: Nothing
        throw(ArgumentError("Type `Nothing` not supported, did you mean `Union{T, Nothing}`?"))
    end

    default = StructUtils.lower(DashiStyle(), _default)

    # we consider nullable types, which correspond to optional fields with no default
    return (T <: Union{Integer, Nothing}) ? IntegerIR(; default) :
        (T <: Union{Number, Nothing}) ? NumberIR(; default) :
        (T <: Union{AbstractString, Symbol, Nothing}) ? StringIR(; default) :
        (T <: Union{Enum, Nothing}) ? StringIR(; default, enum = enum_instances(T)) :
        TrivialIR()
end

# schema for composite structures

function ObjectIR(::Type{T}) where {T}
    properties = Property[]
    tags = fieldtags(DashiStyle(), T)
    defaults = fielddefaults(DashiStyle(), T)

    for field in fieldnames(T)
        key = string(field)
        config = get_dashi(get(tags, field, nothing))
        default = get(defaults, field, nothing)
        S = fieldtype(T, field)
        schema = merge_IR(IR_from_type(S, default), something(config, TrivialIR()))
        is_required = isnothing(default) && !(Nothing <: S)
        push!(properties, Property(key => schema, required = is_required))
    end
    return ObjectIR(; properties)
end
