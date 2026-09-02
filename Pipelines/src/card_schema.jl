# general schema utils

function EmptyTaggedObjectIR(; objects::AbstractDict, additionalProperties::Bool = false, kwargs...)
    objects = Dict{String, ObjectIR}(k => ObjectIR(; additionalProperties) for k in keys(objects))
    return TaggedObjectIR(; objects, kwargs...)
end

additional_conditions(::Type) = StringDict[]

# Card schema

function schema_definitions(variables::AbstractVector)
    variable_schema = StringIR(enum = variables)
    variables_schema = ArrayIR{String}(items = VARIABLE_DEF, default = String[])
    nonempty_variables_schema = ArrayIR{String}(items = VARIABLE_DEF, minItems = 1)
    return StringDict(
        "variable" => emit_json(variable_schema),
        "variables" => emit_json(variables_schema),
        "nonempty_variables" => emit_json(nonempty_variables_schema),
    )
end

function card_schema(
        key::AbstractString, variable_config::Any;
        additionalProperties::Bool = false
    )::StringDict
    schema = card_schema(key; additionalProperties)
    schema["\$defs"] = schema_definitions(variable_config)
    return schema
end

function card_schema(key::AbstractString; additionalProperties::Bool = false)::StringDict
    spec = get_spec(key)
    T = spec.type
    ir = (T <: WildCard) ? WildCardIR(spec.settings) : ObjectIR(T)
    schema::StringDict = emit_json(ir)
    append!(get!(schema, "allOf", StringDict[]), additional_conditions(T))
    # set defaults if not provided by card schema implementation
    schema["properties"]["type"] = StringDict("const" => key)
    ("type" in schema["required"]) || push!(schema["required"], "type")
    get!(schema, "title", spec.label)
    get!(schema, "additionalProperties", additionalProperties)
    return schema
end
