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
function ir_definitions(variables::AbstractVector)
    return StringDict(
        "variable" => StringIR(enum = variables),
        "variables" => ArrayIR{String}(items = VARIABLE_DEF, default = String[]),
        "nonempty_variables" => ArrayIR{String}(items = VARIABLE_DEF, minItems = 1),
    )
end

function schema_definitions(variables::AbstractVector)
    return StringDict(k => json_schema(v) for (k, v) in pairs(ir_definitions(variables)))
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
