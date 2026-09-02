# definitions

const NODE_DEF = ReferenceIR(raw"#/$defs/node")
const GROUP_DEF = ReferenceIR(raw"#/$defs/group")
const COL_DEF = ReferenceIR(raw"#/$defs/col")

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

    properties = [
        Property("nodes" => ArrayIR{String}(; items = NODE_DEF, minItems, maxItems), required = false),
        Property("groups" => ArrayIR{String}(; items = GROUP_DEF, minItems, maxItems), required = false),
        Property("cols" => ArrayIR{String}(; items = COL_DEF, minItems, maxItems), required = false),
        Property("through" => ArrayIR{String}(; items = NODE_DEF, default = []), required = false),
    ]

    object = ObjectIR(; properties)

    schema::StringDict = emit_json(object)
    schema["oneOf"] = [
        StringDict("required" => ["nodes"]),
        StringDict("required" => ["groups"]),
        StringDict("required" => ["cols"]),
    ]
    return schema
end

function one_or_many_schema(
        schema::AbstractDict;
        minItems = nothing, maxItems = nothing, default = nothing
    )
    obj_schema::StringDict = schema
    arr_schema = StringDict(
        "type" => "array",
        "items" => obj_schema,
        "minItems" => minItems,
        "maxItems" => maxItems,
        "default" => default,
    )
    DashiBase.omit_null!(arr_schema)
    obj = StringDict("if" => StringDict("type" => "object"), "then" => obj_schema)
    arr = StringDict("if" => StringDict("type" => "array"), "then" => arr_schema)
    return StringDict("type" => ["object", "array"], "allOf" => [obj, arr])
end

function schema_definitions(variable_config::VariableConfig)
    node_schema = StringIR(enum = variable_config.nodes) |> emit_json
    group_schema = StringIR(enum = variable_config.groups) |> emit_json
    col_schema = StringIR(enum = variable_config.cols) |> emit_json

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

group_schema() = emit_json(VARIABLES_DEF)

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
