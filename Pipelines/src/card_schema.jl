# general schema utils

function EmptyTaggedObjectIR(; objects::AbstractDict, additionalProperties::Bool = false, kwargs...)
    objects = Dict{String, ObjectIR}(k => ObjectIR(; additionalProperties) for k in keys(objects))
    return TaggedObjectIR(; objects, kwargs...)
end

additional_conditions(::Type) = StringDict[]

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
    schema::StringDict = (T <: WildCard) ? wild_card_schema(spec.settings) : emit_json(ObjectIR(T))
    append!(get!(schema, "allOf", StringDict[]), additional_conditions(T))
    # set defaults if not provided by card schema implementation
    schema["properties"]["type"] = StringDict("const" => key)
    ("type" in schema["required"]) || push!(schema["required"], "type")
    get!(schema, "title", spec.label)
    get!(schema, "additionalProperties", additionalProperties)
    return schema
end

# Definitions

const VARIABLE_DEF = ReferenceIR(raw"#/$defs/variable")
const VARIABLES_DEF = ReferenceIR(raw"#/$defs/variables")
const NONEMPTY_VARIABLES_DEF = ReferenceIR(raw"#/$defs/nonempty_variables")

const NODE_DEF = ReferenceIR(raw"#/$defs/node")
const GROUP_DEF = ReferenceIR(raw"#/$defs/group")
const COL_DEF = ReferenceIR(raw"#/$defs/col")
