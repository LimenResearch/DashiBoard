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

    is_required = isnothing(default) && !(Nothing <: T)
    return schema, is_required
end

# schema for composite structures

additional_conditions(::Type) = nothing

function composite_schema(::Type{T}; additionalProperties::Bool = false) where {T}
    properties = StringDict()
    required = String[]
    tags = fieldtags(DashiStyle(), T)
    defaults = fielddefaults(DashiStyle(), T)
    allOf::Union{Vector{Any}, Nothing} = additional_conditions(T)

    for field in fieldnames(T)
        key = string(field)
        config = get_dashi(get(tags, field, nothing))
        default = get(defaults, field, nothing)
        schema, is_required = schema_from_type(fieldtype(T, field), config, default)
        properties[key] = schema
        is_required && push!(required, key)
    end
    return json_object(; properties, additionalProperties, required, allOf)
end

function tagged_schema(f::F, d::AbstractDict; default = nothing) where {F}
    schema = match_property("type" => keys(d); default)

    allOf = StringDict[]
    for (k, v) in pairs(d)
        option_schema = f(v)
        option_schema["properties"]["type"] = true
        cond = match_property("type" => k; default, is_condition = true)
        push!(allOf, conditional_schema(cond, option_schema))
    end
    schema["allOf"] = allOf

    return schema
end

function tagged_composite_schema(d::AbstractDict; default = nothing)
    return tagged_schema(composite_schema, d; default)
end

# atomic JSON schema utils

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

# conditional JSON schema utils

is_match(val, name::AbstractString) = val == name
is_match(val, enum::Union{AbstractSet, AbstractVector}) = val ∉ enum

auto_property(name::AbstractString, _ = nothing) = json_const(name)
auto_property(enum::Union{AbstractSet, AbstractVector}, default = nothing) = json_string(; enum, default)
auto_property(property::AbstractDict, _ = nothing) = property

function match_property(
        (key, x)::Pair{<:AbstractString, <:Union{AbstractString, AbstractSet, AbstractVector, AbstractDict}};
        default = nothing, additionalProperties::Union{Bool, Nothing} = nothing, is_condition::Bool = false
    )
    properties = StringDict(key => auto_property(x, default))
    is_required::Bool, type::Union{String, Nothing} = if is_condition
        # here we only require the property if we need to overwrite a mismatched default
        !isnothing(default) && !is_match(default, x), nothing
    else
        isnothing(default), "object"
    end
    required = is_required ? String[key] : nothing
    return json_config(type; properties, additionalProperties, required)
end

function conditional_schema(condition::AbstractDict, schema::AbstractDict)
    return StringDict("if" => condition, "then" => schema)
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
