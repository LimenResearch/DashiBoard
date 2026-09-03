# Abstract type and basic definitions for IR

abstract type AbstractIR end

Base.show(io::IO, s::AbstractIR) = JSON.json(io, s, omit_null = true)

omit_null!(d::AbstractDict) = filter!(!isnothing ∘ last, d)

maybe_json_schema(s) = s isa AbstractIR ? json_schema(s) : s

"""
    json_schema(s::AbstractIR)

Return JSON schema (as a potentially nested dictionary) from an `AbstractIR` `s`.
"""
function json_schema(s::AbstractIR)
    schema = StructUtils.make(StringDict, s)
    map!(maybe_json_schema, values(schema))
    return omit_null!(schema)
end

struct Property
    key::String
    value::AbstractIR
    required::Bool
end

function Property((key, value)::Pair{<:AbstractString, <:AbstractIR}; required::Bool = true)
    return Property(key, value, required)
end

# Building blocks of IR

struct TrivialIR <: AbstractIR end

@kwarg struct BooleanIR <: AbstractIR
    type::String = "boolean"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    default::Maybe{Bool} = nothing
end

@kwarg struct NumericIR{T <: Real} <: AbstractIR
    type::String = T <: Integer ? "integer" : "number"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    default::Maybe{T} = nothing
    enum::Maybe{Vector{T}} = nothing
    minimum::Maybe{Int} = nothing
    maximum::Maybe{Int} = nothing
    exclusiveMinimum::Maybe{Int} = nothing
    exclusiveMaximum::Maybe{Int} = nothing
end

const IntegerIR = NumericIR{Int}
const NumberIR = NumericIR{Float64}

@kwarg struct StringIR <: AbstractIR
    type::String = "string"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    default::Maybe{String} = nothing
    minLength::Maybe{Int} = nothing
    maxLength::Maybe{Int} = nothing
    enum::Maybe{Vector{String}} = nothing
end

@kwarg struct ReferenceIR <: AbstractIR
    var"$ref"::String
end

@kwarg struct ArrayIR{T, IR <: AbstractIR} <: AbstractIR
    type::String = "array"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    default::Maybe{Vector{T}} = nothing
    items::IR
    minItems::Maybe{Int} = nothing
    maxItems::Maybe{Int} = nothing
end

function ArrayIR{T}(; items::IR = IR_from_type(T, nothing), kwargs...) where {T, IR <: AbstractIR}
    return ArrayIR{T, IR}(; items, kwargs...)
end

@kwarg struct ObjectIR <: AbstractIR
    type::String = "object"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    properties::Vector{Property} = Property[]
    additionalProperties::Bool = false
    constraints::Vector{StringDict} = StringDict[]
end

function json_schema(o::ObjectIR)
    properties = Dict{String, Any}(prop.key => json_schema(prop.value) for prop in o.properties)
    required = String[prop.key for prop in o.properties if prop.required]
    constraints = copy(o.constraints)
    schema = StringDict(
        "type" => "object",
        "title" => o.title,
        "description" => o.description,
        "properties" => properties,
        "allOf" => constraints,
        "additionalProperties" => o.additionalProperties,
        "required" => required
    )
    return omit_null!(schema)
end

@kwarg struct TaggedObjectIR <: AbstractIR
    type::String = "tagged_object"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    objects::Dict{String, ObjectIR} = Dict{String, ObjectIR}()
    options::Vector{String} = collect(String, keys(objects))
    default_option::Maybe{String} = nothing
end

function json_schema(to::TaggedObjectIR)
    required = isnothing(to.default_option) ? ["type"] : String[]
    properties = StringDict(
        "type" => json_schema(StringIR(enum = to.options, default = to.default_option))
    )
    allOf = map(to.options) do option
        schema = json_schema(to.objects[option])
        get!(schema["properties"], "type", true)
        return StringDict(
            "if" => StringDict(
                "properties" => StringDict("type" => StringDict("const" => option)),
                "required" => option == to.default_option ? String[] : ["type"]
            ),
            "then" => schema,
        )
    end
    schema = StringDict(
        "type" => "object",
        "title" => to.title,
        "description" => to.description,
        "properties" => properties,
        "required" => required,
        "allOf" => allOf
    )
    return omit_null!(schema)
end

struct OneOrManyIR{T, IR <: AbstractIR} <: AbstractIR
    array::ArrayIR{T, IR}
    eltype::String
end

function OneOrManyIR{T}(; items::IR, eltype::AbstractString = items.type, kwargs...) where {T, IR <: AbstractIR}
    array = ArrayIR{T}(; items, kwargs...)
    return OneOrManyIR{T, IR}(array, eltype)
end

function json_schema(o::OneOrManyIR)
    return StringDict(
        "type" => [o.eltype, o.array.type],
        "allOf" => [
            Dict("if" => Dict("type" => o.eltype), "then" => json_schema(o.array.items)),
            Dict("if" => Dict("type" => o.array.type), "then" => json_schema(o.array)),
        ]
    )
end

const IR_DICT = Dict{String, Type}(
    "boolean" => IntegerIR,
    "integer" => IntegerIR,
    "number" => NumberIR,
    "string" => StringIR,
    "array" => ArrayIR,
    "object" => ObjectIR,
    "tagged_object" => TaggedObjectIR,
)

choose_IR(x) = IR_DICT[x["type"]]

StructUtils.@choosetype AbstractIR choose_IR
