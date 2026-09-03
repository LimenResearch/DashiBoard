# definitions

const NODE_DEF = ReferenceIR(raw"#/$defs/node")
const GROUP_DEF = ReferenceIR(raw"#/$defs/group")
const COL_DEF = ReferenceIR(raw"#/$defs/col")

# schema definitions

@kwarg struct VariableConfig
    nodes::Maybe{Vector{String}} = nothing
    groups::Maybe{Vector{String}} = nothing
    cols::Maybe{Vector{String}} = nothing
end

function array_schema(
        schema::AbstractDict; minItems = nothing, maxItems = nothing, default = nothing
    )
    arr_schema = StringDict(
        "type" => "array",
        "items" => schema,
        "minItems" => minItems,
        "maxItems" => maxItems,
        "default" => default,
    )
    return DashiBase.omit_null!(arr_schema)
end

function one_or_many_schema(schema::AbstractDict, type = schema["type"]; kwargs...)
    item_schema::StringDict = schema
    arr_schema::StringDict = array_schema(schema; kwargs...)
    item = StringDict("if" => StringDict("type" => type), "then" => item_schema)
    arr = StringDict("if" => StringDict("type" => "array"), "then" => arr_schema)
    return StringDict("type" => [type, "array"], "allOf" => [item, arr])
end

# schema for a `{nodes: str | list[str]}`, `{groups: str | list[str]}`, `{cols: str | list[str]}`
# with a potential `through: list[str]` attribute
function variable_item_schema()
    properties = Dict(
        "nodes" => one_or_many_schema(json_schema(NODE_DEF), "string"),
        "groups" => one_or_many_schema(json_schema(GROUP_DEF), "string"),
        "cols" => one_or_many_schema(json_schema(COL_DEF), "string"),
        "through" => array_schema(json_schema(NODE_DEF), default = [])
    )
    oneOf = [
        StringDict("required" => ["nodes"]),
        StringDict("required" => ["groups"]),
        StringDict("required" => ["cols"]),
    ]

    return StringDict(
        "type" => "object",
        "properties" => properties,
        "additionalProperties" => false,
        "oneOf" => oneOf
    )
end

function schema_definitions(variable_config::VariableConfig)
    node_schema = StringIR(enum = variable_config.nodes) |> json_schema
    group_schema = StringIR(enum = variable_config.groups) |> json_schema
    col_schema = StringIR(enum = variable_config.cols) |> json_schema

    variable_schema = variable_item_schema()
    variables_schema = array_schema(variable_item_schema())
    nonempty_variables_schema = array_schema(variable_item_schema(), minItems = 1)

    return StringDict(
        "node" => node_schema,
        "group" => group_schema,
        "col" => col_schema,
        "variable" => variable_schema,
        "variables" => variables_schema,
        "nonempty_variables" => nonempty_variables_schema,
    )
end

group_schema() = json_schema(VARIABLES_DEF)

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
        cols::Maybe{AbstractVector} = nothing
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
