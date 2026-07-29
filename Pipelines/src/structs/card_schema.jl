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
# e.g., `tagged_streamliner_schema(model_dir, "model")`
function tagged_streamliner_schema(dir, name)
    vals = available_streamliner_configs(dir)
    d = OrderedDict{String, Vector{StringDict}}(x => parse_properties(dir, x) for x in vals)
    return tagged_schema(streamliner_schema, d)
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
    schema::StringDict = (T <: WildCard) ? wild_card_schema(spec.settings) : composite_schema(T)
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
