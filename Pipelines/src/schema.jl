struct DashiStyle <: StructUtils.StructStyle end

StructUtils.lower(::DashiStyle, x::Symbol) = string(x)

StructUtils.lower(::DashiStyle, x::Enum) = string(Symbol(x))

construct(::Type{T}, x) where {T} = StructUtils.make(T, x, DashiStyle())

function get_dashi(nt::NamedTuple, sym::Symbol)
    s = get(nt, sym, nothing)
    return isnothing(s) ? nothing : get(s, :dashi, nothing)
end

_instances(::Type{T}) where {T <: Enum} = instances(T)
_instances(::Type{Union{T, Nothing}}) where {T <: Enum} = instances(T)

enum_instances(T::Type) = String[StructUtils.lower(DashiStyle(), x) for x in _instances(T)]

# generic schema utils

function schema_from_type(T::Type)
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
        nothing
    isnothing(type) || (schema["type"] = type)

    (T <: Union{Enum, Nothing}) && (schema["enum"] = enum_instances(T))

    return schema
end

function schema_from_type(T::Type, config::Union{AbstractDict, Nothing}, default)
    schema = schema_from_type(T)

    isnothing(default) || (schema["default"] = StructUtils.lower(DashiStyle(), default))
    isnothing(config) || merge!(schema, config)

    required = isnothing(default) && !(Nothing <: T)
    return schema, required
end

# note: here we assume that the `key` was already given as required
function match_property(
        (key, name)::Pair{<:AbstractString, <:AbstractString}
    )
    properties = StringDict(key => json_const(name))
    return json_config(; properties)
end

function match_property(
        (key, name)::Pair{<:AbstractString, <:AbstractString},
        default::AbstractString
    )
    properties = StringDict(key => json_const(name))
    required = name == default ? String[] : String[key]
    return json_config(; properties, required)
end

function conditional_schema(condition::AbstractDict, schema::AbstractDict)
    return StringDict("if" => condition, "then" => schema)
end

function conditional_schema(
        (method_key, method_name)::Pair{<:AbstractString, <:AbstractString},
        (options_key, options_schema)::Pair{<:AbstractString, <:AbstractDict},
    )
    condition = match_property(method_key => method_name)
    properties = StringDict(options_key => options_schema)
    # If at least one property of `options_schema` is required,
    # then `options_schema` is required
    required = isempty(options_schema["required"]) ? String[] : String[options_key]
    schema = json_config(; properties, required)
    return conditional_schema(condition, schema)
end

function one_or_many_schema(schema::AbstractDict; kwargs...)
    obj_schema::StringDict = schema
    arr_schema = json_array(; items = obj_schema, kwargs...)
    obj = conditional_schema(json_object(), obj_schema)
    arr = conditional_schema(json_array(), arr_schema)
    return StringDict(
        "type" => ["object", "array"],
        "allOf" => [obj, arr]
    )
end

# schema utils for `method` and `method_options` schemas

function options_schema(::Type{T}; additionalProperties::Bool = false) where {T}
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
    return json_object(; properties, additionalProperties, required)
end

function type_schema(d::AbstractDict; default = nothing, additionalProperties::Bool = false)
    properties = StringDict("type" => json_string(; enum = keys(d), default))
    required = isnothing(default) ? String["type"] : String[]
    return json_object(; properties, additionalProperties, required)
end

function conditional_options_schema(f::F, d::AbstractDict; default = nothing) where {F}
    schema = type_schema(d; default, additionalProperties = true)

    allOf = StringDict[]
    for (k, v) in pairs(d)
        option_schema = f(v)
        option_schema["properties"]["type"] = true
        cond = isnothing(default) ? match_property("type" => k) : match_property("type" => k, default)
        push!(allOf, conditional_schema(cond, option_schema))
    end
    schema["allOf"] = allOf

    return schema
end

function conditional_options_schema(d::AbstractDict; default = nothing)
    return conditional_options_schema(options_schema, d; default)
end

# schema utils for Streamliner cards

function streamliner_schema(configs::AbstractVector; additionalProperties::Bool = false)
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
    return json_object(; properties, additionalProperties, required)
end

# Compute schemas used for model or training in Streamliner,
# e.g., `conditional_streamliner_schemas(model_dir, model_names, "model")`
function conditional_streamliner_schema(dir, name)
    vals = available_streamliner_configs(dir)
    d = OrderedDict{String, Vector{StringDict}}(x => parse_properties(dir, x) for x in vals)
    return conditional_options_schema(streamliner_schema, d)
end

# Card schema

function schema_definitions(variables::AbstractVector)
    variable_schema = json_string(enum = variables)
    variables_schema = json_array(items = JSON_VARIABLE, default = [])
    nonempty_variables_schema = json_array(items = JSON_VARIABLE, minItems = 1)
    return StringDict(
        "variable" => variable_schema,
        "variables" => variables_schema,
        "nonempty_variables" => nonempty_variables_schema,
    )
end

function json_schema(
        key::AbstractString, variables::Any;
        additionalProperties::Bool = false
    )::StringDict
    schema = json_schema(key; additionalProperties)
    schema["\$defs"] = schema_definitions(variables)
    return schema
end

function json_schema(key::AbstractString; additionalProperties::Bool = false)::StringDict
    spec = get_spec(key)
    T = spec.type
    schema::StringDict = (T <: WildCard) ? wild_card_schema(spec.settings) : options_schema(T)
    # set defaults if not provided by card schema implementation
    schema["properties"]["type"] = json_const(key)
    ("type" in schema["required"]) || push!(schema["required"], "type")
    get!(schema, "title", spec.label)
    get!(schema, "additionalProperties", additionalProperties)
    return schema
end

# Definitions

# Note: must keep `valtype::Any` due to a JSONSchema limitation
# see https://github.com/JuliaIO/JSONSchema.jl/issues/81
const JSON_VARIABLE = StringDict("\$ref" => "#/\$defs/variable")
const JSON_VARIABLES = StringDict("\$ref" => "#/\$defs/variables")
const JSON_NONEMPTY_VARIABLES = StringDict("\$ref" => "#/\$defs/nonempty_variables")

const JSON_NODE = StringDict("\$ref" => "#/\$defs/node")
const JSON_GROUP = StringDict("\$ref" => "#/\$defs/group")
const JSON_COL = StringDict("\$ref" => "#/\$defs/col")

# JSON schema utils

nonnothing_dict(; kwargs...) = set_nonnothing!(StringDict(); kwargs...)

function set_nonnothing!(d::AbstractDict; kwargs...)
    for (k, v) in pairs(kwargs)
        isnothing(v) || (d[string(k)] = v)
    end
    return d
end

json_const(k) = StringDict("const" => k)

json_integer(; kwargs...) = json_number("integer"; kwargs...)

function json_number(
        type::AbstractString = "number";
        enum::Union{AbstractVector, Nothing} = nothing,
        minimum::Union{Integer, Nothing} = nothing,
        maximum::Union{Integer, Nothing} = nothing,
        exclusiveMinimum::Union{Integer, Nothing} = nothing,
        exclusiveMaximum::Union{Integer, Nothing} = nothing,
        title::Union{AbstractString, Nothing} = nothing,
        description::Union{AbstractString, Nothing} = nothing,
        default::Union{Number, Nothing} = nothing
    )
    return nonnothing_dict(;
        type = type,
        enum, minimum, maximum,
        exclusiveMinimum, exclusiveMaximum,
        title, description, default
    )
end

function json_string(;
        minLength::Union{Integer, Nothing} = nothing,
        maxLength::Union{Integer, Nothing} = nothing,
        enum::Union{AbstractVector, AbstractSet, Nothing} = nothing,
        title::Union{AbstractString, Nothing} = nothing,
        description::Union{AbstractString, Nothing} = nothing,
        default::Union{AbstractString, Nothing} = nothing
    )
    return nonnothing_dict(;
        type = "string",
        minLength, maxLength, enum,
        title, description, default
    )
end

function json_array(;
        items::Union{AbstractDict, Nothing} = nothing,
        minItems::Union{Integer, Nothing} = nothing,
        maxItems::Union{Integer, Nothing} = nothing,
        title::Union{AbstractString, Nothing} = nothing,
        description::Union{AbstractString, Nothing} = nothing,
        default::Union{AbstractVector, Nothing} = nothing
    )
    return nonnothing_dict(;
        type = "array",
        items, minItems, maxItems,
        title, description, default
    )
end

json_object(; kwargs...) = json_config("object"; kwargs...)

function json_config(
        type::Union{AbstractString, Nothing} = nothing;
        properties::Union{AbstractDict, Nothing} = nothing,
        additionalProperties::Union{Bool, Nothing} = nothing,
        allOf::Union{AbstractVector, Nothing} = nothing,
        anyOf::Union{AbstractVector, Nothing} = nothing,
        oneOf::Union{AbstractVector, Nothing} = nothing,
        required::Union{AbstractVector, Nothing} = nothing,
        title::Union{AbstractString, Nothing} = nothing,
        description::Union{AbstractString, Nothing} = nothing,
        default::Union{AbstractVector, Nothing} = nothing
    )

    return nonnothing_dict(;
        type = type,
        properties, additionalProperties,
        allOf, anyOf, oneOf, required,
        title, description, default
    )
end
