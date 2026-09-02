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
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    default::Union{T, Nothing} = nothing
    enum::Union{Vector{T}, Nothing} = nothing
    minimum::Union{Int, Nothing} = nothing
    maximum::Union{Int, Nothing} = nothing
    exclusiveMinimum::Union{Int, Nothing} = nothing
    exclusiveMaximum::Union{Int, Nothing} = nothing
end

const IntegerIR = NumericIR{Int}
const NumberIR = NumericIR{Float64}

@kwarg struct StringIR <: AbstractIR
    type::String = "string"
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    default::Union{String, Nothing} = nothing
    minLength::Union{Int, Nothing} = nothing
    maxLength::Union{Int, Nothing} = nothing
    enum::Union{Vector{String}, Nothing} = nothing
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
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
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
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    objects::Dict{String, ObjectIR} = Dict{String, ObjectIR}()
    options::Vector{String} = collect(String, keys(objects))
    default_option::Union{String, Nothing} = nothing
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
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    default::Union{Vector{T}, Nothing} = nothing
    items::IR
    minItems::Union{Int, Nothing} = nothing
    maxItems::Union{Int, Nothing} = nothing
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
