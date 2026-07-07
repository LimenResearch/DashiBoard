# schema definitions

function deps_item_schema(; singular::Bool = false)
    min, max = 1, singular ? 1 : nothing

    return Dict(
        "type" => "object",
        "properties" => Dict(
            "nodes" => json_array(JSON_NODE; min, max),
            "groups" => json_array(JSON_GROUP; min, max),
            "cols" => json_array(JSON_COL; min, max),
            "through" => Dict(
                "type" => "array",
                "items" => JSON_NODE,
                "default" => []
            )
        ),
        "oneOf" => [
            Dict("required" => ["nodes"]),
            Dict("required" => ["groups"]),
            Dict("required" => ["cols"]),
        ],
        "additionalProperties" => false
    )
end

function schema_definitions(deps::Deps)
    node_schema = json_enum(deps.nodes)
    group_schema = json_enum(deps.groups)
    col_schema = json_enum(deps.cols)

    item_schema = deps_item_schema()
    singular_item_schema = deps_item_schema(singular = true)

    variable_schema = one_or_many_schema(
        singular_item_schema, Dict("minItems" => 1, "maxItems" => 1)
    )

    variables_schema = one_or_many_schema(
        item_schema, Dict("default" => [])
    )

    nonempty_variables_schema = one_or_many_schema(
        item_schema, Dict("minItems" => 1)
    )

    return Dict(
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
    properties = Dict(name => JSON_VARIABLES for name in grp_names)
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => grp_names,
        "additionalProperties" => false
    )
end
