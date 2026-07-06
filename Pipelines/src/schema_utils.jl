struct DashiStyle <: StructUtils.StructStyle end

StructUtils.lower(::DashiStyle, x::Symbol) = string(x)

StructUtils.lower(::DashiStyle, x::Enum) = string(Symbol(x))

_lower(x) = StructUtils.lower(DashiStyle(), x)

construct(::Type{T}, x) where {T} = StructUtils.make(T, x, DashiStyle())

function get_dashi(nt::NamedTuple, sym::Symbol)
    s = get(nt, sym, nothing)
    return isnothing(s) ? nothing : get(s, :dashi, nothing)
end

_instances(::Type{T}) where {T <: Enum} = instances(T)
_instances(::Type{Union{T, Nothing}}) where {T <: Enum} = _instances(T)

enum_instances(T::Type) = collect(Iterators.map(_lower, _instances(T)))

# generic schema utils

function schema_from_type(T::Type, config::Union{AbstractDict, Nothing}, default)
    schema = StringDict()

    if T <: Nothing
        throw(ArgumentError("Type `Nothing` not supported, did you mean `Union{T, Nothing}`?"))
    end

    # we consider nullable types, which correspond to optional fields with no default
    type = (T <: Union{Integer, Nothing}) ? "integer" :
        (T <: Union{Number, Nothing}) ? "number" :
        (T <: Union{AbstractString, Symbol, Nothing}) ? "string" :
        (T <: Union{AbstractVector, Nothing}) ? "array" :
        (T <: Union{Enum, Nothing}) ? "string" :
        throw(ArgumentError("Type $T not supported in json schema generation."))
    schema["type"] = type

    (T <: Union{Enum, Nothing}) && (schema["enum"] = enum_instances(T))
    isnothing(default) || (schema["default"] = _lower(default))
    isnothing(config) || merge!(schema, config)

    required = isnothing(default) && !(Nothing <: T)
    return schema, required
end

function conditional_schema(condition::AbstractDict, schema::AbstractDict)
    return Dict("if" => condition, "then" => schema)
end

function conditional_schema(
        (method_key, method_name)::Pair{<:AbstractString, <:AbstractString},
        (options_key, options_schema)::Pair{<:AbstractString, <:AbstractDict},
    )
    condition = Dict("properties" => Dict(method_key => Dict("const" => method_name)))
    is_required = !isempty(options_schema["required"])
    schema = Dict(
        "properties" => Dict(options_key => options_schema),
        "required" => is_required ? String[options_key] : String[]
    )
    return conditional_schema(condition, schema)
end

# schema utils for `method` and `method_options` schemas

function options_schema(::Type{T}; additional_properties::Bool = false) where {T}
    properties = StringDict()
    required = String[]
    tags = fieldtags(DashiStyle(), T)
    defaults = fielddefaults(DashiStyle(), T)

    for field in fieldnames(T)
        key = string(field)
        config = get_dashi(tags, field)
        default = get(defaults, field, nothing)
        schema, is_required = schema_from_type(fieldtype(T, field), config, default)
        properties[key] = schema
        is_required && push!(required, key)
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => additional_properties
    )
end

function conditional_options_schemas(d)
    return [
        conditional_schema("method" => k, "method_options" => options_schema(T))
            for (k, T) in pairs(d)
    ]
end

# schema utils for Streamliner cards

function streamliner_schema(configs::AbstractVector; additional_properties::Bool = false)
    properties = StringDict()
    required = String[]
    for config in configs
        schema = StringDict(config)
        key::String = pop!(schema, "key")
        # potentially allow a custom keyword for this
        is_required = !haskey(schema, "default")
        properties[key] = schema
        is_required && push!(required, key)
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => additional_properties
    )
end

# Compute schemas used for model or training in Streamliner,
# e.g., `conditional_options_schemas(model_dir, model_names, "model")`
function conditional_streamliner_schemas(dir, vals, name)
    return map(vals) do x
        schema = streamliner_schema(parse_properties(dir, x))
        conditional_schema(name => x, string(name, "_", "options") => schema)
    end
end

# Definitions

# Note: must keep `valtype::Any` due to a JSONSchema limitation
# see https://github.com/JuliaIO/JSONSchema.jl/issues/81
const JSON_VARIABLE = StringDict("\$ref" => "#/\$defs/variable")
const JSON_VARIABLES = StringDict("\$ref" => "#/\$defs/variables")
const JSON_NONEMPTY_VARIABLES = StringDict("\$ref" => "#/\$defs/nonempty_variables")

const JSON_NODES = StringDict("\$ref" => "#/\$defs/nodes")
const JSON_NODE = StringDict("\$ref" => "#/\$defs/node")
const JSON_GROUP = StringDict("\$ref" => "#/\$defs/group")
const JSON_COL = StringDict("\$ref" => "#/\$defs/col")

# JSON schema utils

json_integer(; kwargs...) = json_number("integer"; kwargs...)

function json_number(
        type::AbstractString = "number";
        min::Union{Integer, Nothing} = nothing,
        max::Union{Integer, Nothing} = nothing,
        exclusive_min::Union{Integer, Nothing} = nothing,
        exclusive_max::Union{Integer, Nothing} = nothing,
    )
    schema = Dict{String, Any}("type" => type)
    isnothing(min) || (schema["minimum"] = min)
    isnothing(max) || (schema["maximum"] = max)
    isnothing(exclusive_min) || (schema["exclusiveMinimum"] = exclusive_min)
    isnothing(exclusive_max) || (schema["exclusiveMaximum"] = exclusive_max)
    return schema
end

function json_string(; min::Integer = 0)
    return Dict("type" => "string", "minLength" => min)
end

json_enum(options) = json_enum("string", options)

function json_enum(type::AbstractString, options)
    _options = options isa AbstractVector ? options : collect(options)
    return Dict("type" => type, "enum" => options)
end
