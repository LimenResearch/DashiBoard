# general schema utils

function EmptyTaggedObjectIR(; objects::AbstractDict, additionalProperties::Bool = false, kwargs...)
    objects = Dict{String, ObjectIR}(k => ObjectIR(; additionalProperties) for k in keys(objects))
    return TaggedObjectIR(; objects, kwargs...)
end

# Card schema

"""
    ir_definitions(variables::AbstractVector)

Return the shared `\$defs` entries as IR nodes, for a renderer to resolve `ReferenceIR`s against.
`schema_definitions` is this projected through `json_schema`, so the two cannot drift.
"""
function ir_definitions(variables::Maybe{AbstractVector})
    return StringDict(
        "variable" => StringIR(enum = variables),
        "variables" => ArrayIR(items = VARIABLE_DEF, default = String[]),
        "nonempty_variables" => ArrayIR(items = VARIABLE_DEF, minItems = 1),
    )
end

function schema_definitions(variable_config::Any)
    return map_into(json_schema, StringDict, ir_definitions(variable_config))
end

function card_schema(
        key::AbstractString, variable_config::Any;
        additionalProperties::Bool = false
    )::StringDict
    schema = card_schema(key; additionalProperties)
    schema["\$defs"] = schema_definitions(variable_config)
    return schema
end

"""
    card_ir(key::AbstractString)

Return the intermediate representation for card `key` — the artefact a UI renders from, as
opposed to the JSON Schema it validates with. Both come from this one traversal: `card_schema`
is defined as `json_schema(card_ir(key))` plus the type discriminator, so a divergence between
them is a bug in one function rather than two descriptions drifting apart.

The IR is independent of the variable vocabulary; its `ReferenceIR`s are resolved against
[`ir_definitions`](@ref).
"""
function card_ir(key::AbstractString)
    spec = get_spec(key)
    T = spec.type
    ir = (T <: WildCard) ? WildCardIR(spec.settings) : ObjectIR(T)
    # The card's label belongs in the IR: a renderer needs it, and it saves `card_schema`
    # annotating a built schema. `something` mirrors `card_schema`'s `get!` semantics, so a
    # card that sets its own title keeps it.
    return ObjectIR(;
        title = something(ir.title, spec.label),
        ir.description, ir.properties, ir.additionalProperties, ir.constraints,
    )
end

function card_schema(key::AbstractString; additionalProperties::Bool = false)::StringDict
    spec = get_spec(key)
    schema::StringDict = json_schema(card_ir(key))
    # set defaults if not provided by card schema implementation
    schema["properties"]["type"] = StringDict("const" => key)
    ("type" in schema["required"]) || push!(schema["required"], "type")
    get!(schema, "title", spec.label)
    get!(schema, "additionalProperties", additionalProperties)
    return schema
end

"""
    card_issues(card, variable_config; base = "", culprit = "card")

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
        card::AbstractDict, variable_config::Any;
        base::AbstractString = "", culprit = "card"
    )
    schema = JSONSchema.Schema(card_schema(card["type"], variable_config))
    issue = JSONSchema.validate(card, schema)
    errors = isnothing(issue) ? SchemaValidationError[] :
        [schema_validation_error(culprit, base, card, issue)]
    return map(issue_report, errors)
end
