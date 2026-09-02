# ObjectIR

emit_json(s::AbstractDict) = s

abstract type AbstractIR end

Base.show(io::IO, s::AbstractIR) = JSON.json(io, s, omit_null = true)

omit_null!(d::AbstractDict) = filter!(!isnothing ∘ last, d)

_emit_json(s::AbstractIR) = to_config(s)

emit_json(s::AbstractIR) = omit_null!(_emit_json(s))

StructUtils.lower(::DashiStyle, s::AbstractIR) = emit_json(s)

struct TrivialIR <: AbstractIR end

@kwarg struct NumericIR{T <: Real} <: AbstractIR
    type::String = "number"
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    default::Union{T, Nothing} = nothing
    enum::Union{Vector{T}, Nothing} = nothing
    minimum::Union{Int, Nothing} = nothing
    maximum::Union{Int, Nothing} = nothing
    exclusiveMinimum::Union{Int, Nothing} = nothing
    exclusiveMaximum::Union{Int, Nothing} = nothing
end

NumberIR(::Type{T} = Float64; kwargs...) where {T <: Real} = NumericIR{T}(; type = "number", kwargs...)

IntegerIR(::Type{T} = Int; kwargs...) where {T <: Integer} = NumericIR{T}(; type = "integer", kwargs...)

@kwarg struct StringIR <: AbstractIR
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

Property((key, value)::Pair; required::Bool = true) = Property(key, value, required)

@kwarg struct ObjectIR <: AbstractIR
    type::String = "object"
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    properties::Vector{Property} = Property[]
    additionalProperties::Bool = false
end

function _emit_json(o::ObjectIR)
    properties = Dict{String, Any}(prop.key => emit_json(prop.value) for prop in o.properties)
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
    type::String = "tagged"
    title::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
    objects::Dict{String, ObjectIR} = Dict{String, ObjectIR}()
    options::Vector{String} = collect(String, keys(objects))
    default_option::Union{String, Nothing} = nothing
end

function _emit_json(to::TaggedObjectIR)
    required = isnothing(to.default_option) ? ["type"] : String[]
    properties = StringDict(
        "type" => emit_json(StringIR(enum = to.options, default = to.default_option))
    )
    allOf = map(to.options) do option
        schema = emit_json(to.objects[option])
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
