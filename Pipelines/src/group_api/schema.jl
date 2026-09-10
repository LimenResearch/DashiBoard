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

# IR for a `{nodes: str | list[str]}`, `{groups: str | list[str]}`, `{cols: str | list[str]}`
# with a potential `through: list[str]` attribute
function variable_item_IR()
    properties = [
        Property("nodes" => OneOrManyIR{String}(; items = NODE_DEF, eltype = "string"), required = false),
        Property("groups" => OneOrManyIR{String}(; items = GROUP_DEF, eltype = "string"), required = false),
        Property("cols" => OneOrManyIR{String}(; items = COL_DEF, eltype = "string"), required = false),
        Property("through" => ArrayIR{String}(; items = NODE_DEF, default = []), required = false),
    ]
    oneOf = [
        StringDict("required" => ["nodes"]),
        StringDict("required" => ["groups"]),
        StringDict("required" => ["cols"]),
    ]
    return ObjectIR(; properties, constraints = [Dict("oneOf" => oneOf)])
end

"""
    ir_definitions(variable_config::VariableConfig)

The group dialect's shared `\$defs` entries as IR nodes — what a renderer builds from.
`schema_definitions` is this projected through `json_schema`, so the two cannot drift, exactly as
for the flat dialect in `card_schema.jl`.

Where the flat dialect's `variable` is a string enum of column names, here it is a *selector
object*: `{nodes|groups|cols: str | list[str], through: list[str]}`, gated so exactly one of the
three is present.
"""
function ir_definitions(variable_config::VariableConfig)
    return StringDict(
        "node" => StringIR(enum = variable_config.nodes),
        "group" => StringIR(enum = variable_config.groups),
        "col" => StringIR(enum = variable_config.cols),
        "variable" => variable_item_IR(),
        "variables" => ArrayIR{AbstractDict}(items = variable_item_IR()),
        "nonempty_variables" => ArrayIR{AbstractDict}(items = variable_item_IR(), minItems = 1),
    )
end

function schema_definitions(variable_config::VariableConfig)
    return StringDict(k => json_schema(v) for (k, v) in pairs(ir_definitions(variable_config)))
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
