# ObjectIR

abstract type AbstractIR end

Base.show(io::IO, s::AbstractIR) = JSON.json(io, s, omit_null = true)

omit_null!(d::AbstractDict) = filter!(!isnothing ∘ last, d)

_json_schema(s::AbstractIR) = to_config(s)

"""
    json_schema(s::AbstractIR)

Return JSON schema (as a potentially nested dictionary) from an `AbstractIR` `s`.
"""
json_schema(s::AbstractIR) = omit_null!(_json_schema(s))

StructUtils.lower(::DashiStyle, s::AbstractIR) = json_schema(s)

struct TrivialIR <: AbstractIR end

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

struct Property
    key::String
    value::AbstractIR
    required::Bool
end

function Property((key, value)::Pair{<:AbstractString, <:AbstractIR}; required::Bool = true)
    return Property(key, value, required)
end

@kwarg struct ObjectIR <: AbstractIR
    type::String = "object"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    properties::Vector{Property} = Property[]
    additionalProperties::Bool = false
end

function _json_schema(o::ObjectIR)
    properties = Dict{String, Any}(prop.key => json_schema(prop.value) for prop in o.properties)
    required = String[prop.key for prop in o.properties if prop.required]
    return StringDict(
        "type" => "object",
        "title" => o.title,
        "description" => o.description,
        "properties" => properties,
        "additionalProperties" => o.additionalProperties,
        "required" => required
    )
end

@kwarg struct TaggedObjectIR <: AbstractIR
    type::String = "tagged_object"
    title::Maybe{String} = nothing
    description::Maybe{String} = nothing
    objects::Dict{String, ObjectIR} = Dict{String, ObjectIR}()
    options::Vector{String} = collect(String, keys(objects))
    default_option::Maybe{String} = nothing
end

function _json_schema(to::TaggedObjectIR)
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
    return StringDict(
        "type" => "object",
        "title" => to.title,
        "description" => to.description,
        "properties" => properties,
        "required" => required,
        "allOf" => allOf
    )
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

const IR_DICT = Dict{String, Type}(
    "integer" => IntegerIR,
    "number" => NumberIR,
    "string" => StringIR,
    "object" => ObjectIR,
    "tagged_object" => TaggedObjectIR,
    "array" => ArrayIR,
)

choose_IR(x) = IR_DICT[x["type"]]

StructUtils.@choosetype AbstractIR choose_IR
