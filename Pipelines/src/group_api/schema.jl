# schema definitions

@kwarg struct VariableConfig
    nodes::Union{Vector{String}, Nothing} = nothing
    groups::Union{Vector{String}, Nothing} = nothing
    cols::Union{Vector{String}, Nothing} = nothing
end

# schema for a `{nodes: [...]}`, `{groups: [...]}`, `{cols: [...]}`
# with a potential `through: [...]` attribute
function deps_item_schema(; singular::Bool = false)
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

    item_schema = deps_item_schema()
    singular_item_schema = deps_item_schema(singular = true)

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

function groups_schema(variable_config::VariableConfig)
    schema = groups_schema(variable_config.groups)
    schema["\$defs"] = schema_definitions(variable_config)
    return schema
end

function groups_schema(grp_names::AbstractVector)
    properties = StringDict()
    for name in grp_names
        properties[name] = JSON_VARIABLES
    end
    return json_object(; properties, additionalProperties = false, required = grp_names)
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
    node_labels = (get(n, "label", nothing) for n in nodes)
    grp_names = collect(String, keys(groups))
    variable_config = VariableConfig(
        nodes = collect(String, Iterators.filter(!isnothing, node_labels)),
        groups = grp_names,
        cols = cols
    )

    grp_schema = JSONSchema.Schema(groups_schema(variable_config))
    card_schemas = Dict{String, JSONSchema.Schema}()
    for n in nodes
        key = n["card"]["type"]
        card_schemas[key] = JSONSchema.Schema(card_schema(key, variable_config))
    end

    grp_issue = JSONSchema.validate(groups, grp_schema)
    isnothing(grp_issue) || throw(SchemaValidationError("groups", grp_issue))

    for (i, node) in enumerate(nodes)
        card = node["card"]
        card_schema = card_schemas[card["type"]]
        issue = JSONSchema.validate(card, card_schema)
        isnothing(issue) || throw(SchemaValidationError("card in node $(i)", issue))
    end
    return
end
