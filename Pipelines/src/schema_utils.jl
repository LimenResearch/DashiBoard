struct DashiStyle <: StructUtils.StructStyle end

StructUtils.lower(::DashiStyle, x::Symbol) = string(x)

StructUtils.lower(::DashiStyle, x::Enum) = string(Symbol(x))

construct(::Type{T}, x) where {T} = StructUtils.make(T, x, DashiStyle())

function get_dashi(nt::NamedTuple, sym::Symbol)
    s = get(nt, sym, nothing)
    return isnothing(s) ? nothing : get(s, :dashi, nothing)
end

function enum_instances(::Type{T}) where {T <: Enum}
    return [StructUtils.lower(DashiStyle(), x) for x in instances(T)]
end

nullable(s) = StringDict("anyOf" => [s, Dict("type" => "null")])

# generic schema utils

struct EnrichedSchema
    schema::StringDict
    required::Bool
end

function enrich_schema(schema::AbstractDict; nullable::Bool = false)
    default = get(schema, "default", nothing)
    return if nullable
        EnrichedSchema(Pipelines.nullable(schema), false)
    else
        EnrichedSchema(schema, isnothing(default))
    end
end

function enrich_schema(T::Type, config::Union{AbstractDict, Nothing}, default)
    schema = StringDict()

    # FIXME: this is internal
    S = Base.nonnothingtype(T)

    type = (S <: Integer) ? "integer" :
        (S <: Number) ? "number" :
        (S <: Union{AbstractString, Symbol}) ? "string" :
        (S <: AbstractVector) ? "array" :
        (S <: Enum) ? "string" :
        throw(ArgumentError("Type $T not supported in json schema generation."))
    schema["type"] = type

    (S <: Enum) && (schema["enum"] = enum_instances(S))
    isnothing(default) || (schema["default"] = StructUtils.lower(DashiStyle(), default))
    isnothing(config) || merge!(schema, config)

    return enrich_schema(schema; nullable = (Nothing <: T))
end

function conditional_schema(
        (options_key, options_schema)::Pair{<:AbstractString, <:AbstractDict},
        (method_key, method_name)::Pair{<:AbstractString, <:AbstractString}
    )
    is_required = !isempty(options_schema["required"])
    return Dict(
        "if" => Dict("properties" => Dict(method_key => Dict("const" => method_name))),
        "then" => Dict(
            "properties" => Dict(options_key => options_schema),
            "required" => is_required ? String[options_key] : String[]
        )
    )
end

# schema utils for `method` and `method_options` schemas

function options_schema(::Type{T}) where {T}
    properties = StringDict()
    required = String[]
    tags = fieldtags(DashiStyle(), T)
    defaults = fielddefaults(DashiStyle(), T)

    for field in fieldnames(T)
        key = string(field)
        config = get_dashi(tags, field)
        default = get(defaults, field, nothing)
        es = enrich_schema(fieldtype(T, field), config, default)
        properties[key] = es.schema
        es.required && push!(required, key)
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

function conditional_options_schemas(d)
    return [
        conditional_schema("method_options" => options_schema(T), "method" => k)
            for (k, T) in pairs(d)
    ]
end

# schema utils for Streamliner cards

function streamliner_schema(configs::AbstractVector)
    properties = StringDict()
    required = String[]
    for config in configs
        _config = StringDict(config)
        key::String = pop!(_config, "key")
        nullable::Bool = pop!(_config, "nullable", false)
        es = enrich_schema(_config; nullable)
        properties[key] = es.schema
        es.required && push!(required, key)
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

# Compute schemas used for model or training in Streamliner,
# e.g., `conditional_options_schemas(model_dir, model_names, "model")`
function conditional_streamliner_schemas(dir, vals, name)
    return map(vals) do x
        schema = streamliner_schema(parse_properties(dir, x))
        conditional_schema(string(name, "_", "options") => schema, name => x)
    end
end

# Definitions

# Note: must keep `valtype::Any` due to a JSONSchema limitation
const JSON_VARIABLE = StringDict("\$ref" => "#/\$defs/variable")
const JSON_VARIABLES = StringDict("\$ref" => "#/\$defs/variables")
const JSON_NONEMPTY_VARIABLES = StringDict("\$ref" => "#/\$defs/nonempty_variables")

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
