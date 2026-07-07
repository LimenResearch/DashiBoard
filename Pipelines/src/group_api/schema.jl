# schema definitions

function deps_item_schema(; singular::Bool = false)
    minItems, maxItems = 1, singular ? 1 : nothing

    return StringDict(
        "type" => "object",
        "properties" => StringDict(
            "nodes" => json_array(; items = JSON_NODE, minItems, maxItems),
            "groups" => json_array(; items = JSON_GROUP, minItems, maxItems),
            "cols" => json_array(; items = JSON_COL, minItems, maxItems),
            "through" => StringDict(
                "type" => "array",
                "items" => JSON_NODE,
                "default" => []
            )
        ),
        "oneOf" => [
            StringDict("required" => ["nodes"]),
            StringDict("required" => ["groups"]),
            StringDict("required" => ["cols"]),
        ],
        "additionalProperties" => false
    )
end

function schema_definitions(deps::Deps)
    node_schema = json_string(enum = deps.nodes)
    group_schema = json_string(enum = deps.groups)
    col_schema = json_string(enum = deps.cols)

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

function groups_schema(deps::Deps)
    schema = groups_schema(deps.groups)
    schema["\$defs"] = schema_definitions(deps)
    return schema
end

function groups_schema(grp_names::AbstractVector)
    properties = StringDict(name => JSON_VARIABLES for name in grp_names)
    return StringDict(
        "type" => "object",
        "properties" => properties,
        "required" => grp_names,
        "additionalProperties" => false
    )
end
