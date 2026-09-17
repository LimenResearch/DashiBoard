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

"""
    SchemaValidationError(culprit, pointer_base, object, issue)

`culprit` is prose for `showerror`. `pointer_base` is the JSON Pointer of `object` within the
*document*, and `object` is the fragment that was validated — together they let `issue_report`
address a failure from the document root rather than from whichever fragment the validator
happened to be handed, which is ambiguous the moment a document holds two cards.
"""
struct SchemaValidationError{I, O} <: Exception
    culprit::String
    pointer_base::String
    object::O
    issue::I
end

function Base.showerror(io::IO, err::SchemaValidationError)
    print(io, "Schema Validation Error")
    isempty(err.culprit) ? println(io) : println(io, " for ", err.culprit)
    return show(io, err.issue)
end

"""
    SchemaValidationErrors(errors)

Every schema failure in one document, rather than whichever came first (A11).

Validation used to `throw` on the first bad group or card, so a document with two mistakes
reported one and hid the other — and fixing it revealed the next, one round trip at a time. Worse,
groups were checked before cards, so a single bad group hid every card in the document.

This is the only type validation throws, singular case included: a caller that reads one shape is
a caller that cannot forget the plural one exists.
"""
struct SchemaValidationErrors <: Exception
    errors::Vector{SchemaValidationError}
end

function Base.showerror(io::IO, err::SchemaValidationErrors)
    n = length(err.errors)
    n == 1 || println(io, n, " schema validation errors:")
    for e in err.errors
        showerror(io, e)
        println(io)
    end
    return
end

escape_pointer(token::AbstractString) = replace(token, "~" => "~0", "/" => "~1")

"""
    json_pointer(base, path, object)

Convert a `JSONSchema.SingleIssue` path — `"[method][dissimilarity][p]"` — to a JSON Pointer
rooted at `base`.

Two things make this less mechanical than it looks, both measured rather than read:

  * `path` indexes arrays **the Julia way**. The third element of `inputs` reports `[inputs][3]`,
    and a JSON Pointer counts from zero, so array steps subtract one. Skip this and the form
    highlights the wrong row — which is worse than not highlighting one.
  * Whether a step *is* an array step cannot be recovered from the path, since `"1"` is a legal
    object key. So this walks `object` alongside the path and asks what it actually found.
"""
function json_pointer(base::AbstractString, path::AbstractString, object)
    io = IOBuffer()
    print(io, base)
    current = object
    for m in eachmatch(r"\[([^\]]*)\]", path)
        token = m.captures[1]
        index = current isa AbstractVector ? tryparse(Int, token) : nothing
        if !isnothing(index)
            print(io, '/', index - 1)
            current = checkbounds(Bool, current, index) ? current[index] : nothing
        else
            print(io, '/', escape_pointer(token))
            current = current isa AbstractDict ? get(current, token, nothing) : nothing
        end
    end
    return String(take!(io))
end

"""
    issue_report(err::SchemaValidationError)

A validation failure as data rather than prose: where it happened, which keyword failed, and —
where the validator carries it — what would have been accepted (A7).

The distinction that matters is between a form that can offer a correction and one that can only
say no. An `enum` failure arrives with the values that *are* allowed; a `required` failure arrives
with the name that is absent and a `related` pointer to the control that should hold it.

`required` needs that help because it reports at the **parent** path and carries *every* required
name in `val`, not the missing one — so neither half identifies the control on its own.

`severity` is `"error"` for every schema issue; warnings are emitted elsewhere with the same shape.
"""
issue_report(errs::SchemaValidationErrors) = map(issue_report, errs.errors)

function issue_report(err::SchemaValidationError)
    issue = err.issue
    pointer = json_pointer(err.pointer_base, issue.path, err.object)

    # `val` on a variant-name enum is a lazy `KeySet` over the live registry, not a `Vector`;
    # it has to be collected before it can cross a serialisation boundary.
    allowed = issue.reason == "enum" ? collect(Any, issue.val) :
        issue.reason == "const" ? Any[issue.val] : nothing

    absent = String[]
    if issue.reason == "required" && issue.val isa AbstractVector && issue.x isa AbstractDict
        absent = collect(String, setdiff(issue.val, collect(keys(issue.x))))
    end

    return (;
        pointer,
        reason = issue.reason,
        # A schema failure is always an error: the document cannot be built. The field exists
        # so that the same list can carry warnings — an output that overwrites a column, say —
        # and a client tells the two apart without a second list.
        severity = "error",
        # For `required` the offending value is the whole container, which says nothing a pointer
        # has not already said and costs a copy of the card to send.
        found = issue.reason == "required" ? nothing : issue.x,
        allowed,
        missing = absent,
        related = [string(pointer, '/', escape_pointer(name)) for name in absent],
        message = sprint(showerror, err),
    )
end

"""
    card_issues(card, variable_config; base = "")

Validate one card against its own schema, and report what failed as data.

The targeted half of `validate_pipeline_schema`. A form editing a single card does not need a
whole document resolved to learn that `method` has not been chosen — that question is answerable
from the card and the vocabulary alone, and asking it this way costs one schema build instead of a
graph walk over every other card.

`base` is where the card sits in the document, so the pointers come back document-relative and a
client reads them exactly as it reads a probe's. Left empty they are card-relative, which is what
a caller holding one card in isolation wants.

What it deliberately cannot answer: anything about the *graph*. Whether a referenced node actually
produces the column named through it, whether two cards collide on an id, whether the whole thing
is acyclic — all of those need the other cards, and `Pipeline` is where they are asked.
"""
function card_issues(
        card::AbstractDict, variable_config::VariableConfig;
        base::AbstractString = ""
    )
    schema = JSONSchema.Schema(card_schema(card["type"], variable_config))
    issue = JSONSchema.validate(card, schema)
    errors = isnothing(issue) ? SchemaValidationError[] :
        [SchemaValidationError("card", base, card, issue)]
    return map(issue_report, errors)
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

    # Collected, not thrown one at a time (A11). Groups first because that is document order, but
    # a bad group no longer stops the cards from being looked at.
    errors = SchemaValidationError[]

    for (grp_key, grp_val) in pairs(groups)
        issue = JSONSchema.validate(grp_val, grp_schema)
        isnothing(issue) || push!(
            errors,
            SchemaValidationError(
                "group $(grp_key)", "/groups/" * escape_pointer(string(grp_key)), grp_val, issue
            )
        )
    end

    for (i, node) in enumerate(nodes)
        card = node["card"]
        card_schema = card_schemas[card["type"]]
        issue = JSONSchema.validate(card, card_schema)
        isnothing(issue) || push!(
            errors,
            SchemaValidationError("card in node $(i)", "/nodes/$(i - 1)/card", card, issue)
        )
    end

    # One issue per card is still all JSONSchema.jl offers — `validate` returns a `SingleIssue` —
    # so this widens the report across the document, not within a card. A `required` failure does
    # carry every absent name at once, which is why that common case looks complete either way.
    isempty(errors) || throw(SchemaValidationErrors(errors))
    return
end
