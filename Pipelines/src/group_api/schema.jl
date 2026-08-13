# schema definitions

@kwarg struct VariableConfig
    nodes::Union{Vector{String}, Nothing} = nothing
    groups::Union{Vector{String}, Nothing} = nothing
    cols::Union{Vector{String}, Nothing} = nothing
end

# schema for a `{nodes: [...]}`, `{groups: [...]}`, `{cols: [...]}`
# with a potential `through: [...]` attribute
function variable_item_schema(; singular::Bool = false)
    minItems, maxItems = 1, singular ? 1 : nothing

    properties = StringDict(
        "nodes" => json_array(; items = JSON_NODE, minItems, maxItems),
        "groups" => json_array(; items = JSON_GROUP, minItems, maxItems),
        "cols" => json_array(; items = JSON_COL, minItems, maxItems),
        "through" => json_array(; items = JSON_NODE, default = [])
    )
    oneOf = [
        json_config(required = ["nodes"]),
        json_config(required = ["groups"]),
        json_config(required = ["cols"]),
    ]
    return json_object(; properties, additionalProperties = false, oneOf)
end

function schema_definitions(variable_config::VariableConfig)
    node_schema = json_string(enum = variable_config.nodes)
    group_schema = json_string(enum = variable_config.groups)
    col_schema = json_string(enum = variable_config.cols)

    item_schema = variable_item_schema()
    singular_item_schema = variable_item_schema(singular = true)

    variable_schema = one_or_many_schema(singular_item_schema, minItems = 1, maxItems = 1)
    variables_schema = one_or_many_schema(item_schema, default = [])
    nonempty_variables_schema = one_or_many_schema(item_schema, minItems = 1)

    return StringDict(
        "node" => node_schema,
        "group" => group_schema,
        "col" => col_schema,
        "variable" => variable_schema,
        "variables" => variables_schema,
        "nonempty_variables" => nonempty_variables_schema,
    )
end

group_schema() = copy(JSON_VARIABLES)

function group_schema(variable_config::VariableConfig)
    schema = group_schema()
    schema["\$defs"] = schema_definitions(variable_config)
    return schema
end

# Validation

struct SchemaValidationError{I} <: Exception
    culprit::String
    issue::I
end

function Base.showerror(io::IO, err::SchemaValidationError)
    print(io, "Schema Validation Error")
    isempty(err.culprit) ? println(io) : println(io, " for ", err.culprit)
    return show(io, err.issue)
end

function validate_pipeline_schema(
        nodes::AbstractVector,
        groups::AbstractDict,
        cols::Union{AbstractVector, Nothing} = nothing
    )
    variable_config = VariableConfig(
        nodes = get_id.(nodes), groups = collect(String, keys(groups)), cols = cols
    )

    grp_schema = JSONSchema.Schema(group_schema(variable_config))
    card_schemas = Dict{String, JSONSchema.Schema}()
    for n in nodes
        key = n["card"]["type"]
        card_schemas[key] = JSONSchema.Schema(card_schema(key, variable_config))
    end

    for (grp_key, grp_val) in pairs(groups)
        issue = JSONSchema.validate(grp_val, grp_schema)
        isnothing(issue) || throw(SchemaValidationError("group $(grp_key)", issue))
    end

    for (i, node) in enumerate(nodes)
        card = node["card"]
        card_schema = card_schemas[card["type"]]
        issue = JSONSchema.validate(card, card_schema)
        isnothing(issue) || throw(SchemaValidationError("card in node $(i)", issue))
    end
    return
end
