# 07 — JSON Schema and the UI: how a card types itself

Background for anyone implementing A1a, A3 or A7. Explains the mechanism the refactor is built
on, and — more usefully — where it stops working, since every finding in the briefs landed on one
of those seams.

Line numbers are against DashiBoard `main` at `e6f4794`.

---

## The one idea

The schema does not *describe* a card type. It is a **projection** of it. Every constraint the UI
enforces is one the Julia type or its `dashi` tag already stated, and there is nowhere else a card's
shape is written down.

"Robust typing" here does not mean the types are checked carefully. It means there is only one place
to check.

---

## Definition time — three carriers

Exactly three things about each field carry information downstream:

| carrier | carries |
|---|---|
| the Julia field type | the JSON type; for a type parameter, the admissible variants |
| the default, or its absence | requiredness |
| the `dashi` tag | everything the type system cannot express |

The tag is not a UI vocabulary that resembles JSON Schema — `json_integer(minimum = 1)` **is** a
JSON Schema fragment. That is why §4 could adopt `title` and `description` without inventing
anything.

---

## Projection time — `composite_schema`

`Pipelines/src/structs/json_schema.jl:38-54` walks `fieldnames(T)` and fuses the three facts per
field. Two mechanics matter:

**`Union{T, Nothing}` is how optionality is spelled.** `schema_from_type` tests
`T <: Union{Integer, Nothing}`, so a nullable integer and a plain integer take the same branch.
Optionality is recovered separately: `is_required = isnothing(default) && !(Nothing <: T)`
(`json_schema.jl:30`).

**`required` is derived, never declared.** A field is required because it has no default and cannot
be `nothing`. Nobody writes a `required` list; the struct already said it.

### The projection is only as complete as the types it has met

The type mapping (`json_schema.jl:11-16`) is an ordered chain of `<:` tests, and on `main` there is
**no `Bool` branch**. Because `Bool <: Integer` in Julia, a boolean field would project to
`{"type": "integer"}` — JSON `true` rejected, `1` accepted.

It has never fired because no card has a boolean field. `WildCardSettings`
(`cards/wild.jl:1-6`) is handled by `wild_card_schema` rather than `composite_schema`, and
`rescale.jl:187` is a keyword argument, not a struct field. The branch exists on
`ds-emergencyclustering` with a comment explaining the ordering, so someone met it there.

**The gap is invisible until someone adds a boolean field.** Treat the mapping as an inventory of
types encountered so far, not as a total function.

---

## Specialisation time — why this is a UI contract and not just a schema

`card_schema(key, variable_config)` (`structs/card_schema.jl:38-45`) attaches `$defs` whose enums
come from the **current pipeline**: which nodes exist, which groups, which columns.

So a client does not receive "the schema for a `ClusterCard`". It receives "the schema for a
`ClusterCard` at this point in this user's pipeline, thirty seconds after they added a rescale node".

**The schema is a function of context, not a static artefact.** Two consequences:

- Build-time code generation cannot work. A generated TypeScript type cannot know which columns
  exist in a pipeline that does not exist yet.
- §3's rule against computing enums in the browser is not stylistic. The browser would be
  recomputing something the server already knows exactly.

One trap: `VariableConfig`'s fields treat `nothing` as *unconstrained*, not empty
(`group_api/schema.jl:3-7`). Omitting `cols` yields a schema with no column enum at all, so a card
naming a nonexistent column validates and fails later at SQL execution. **A caller must always send
`cols`.**

---

## Composition time — how nesting types itself

A field whose type is an abstract parameter becomes a discriminated union. `tagged_composite_schema`
walks the registry — an `OrderedDict{String, Type}` — and emits an enum gate on `type`, then `allOf`
of `{if type == k, then composite_schema(V)}` (`json_schema.jl:56-73`).

**The type bound does the narrowing for free.** `KMeansMethod{D <: DissimilarityMethod}` and
`DBSCANMethod{D <: MetricMethod}` both have a field named `dissimilarity`, offering nine options and
seven respectively — measured (`cards/cluster.jl:20`, `:43`). Nothing
in the schema layer declares "DBSCAN accepts only true metrics". The KD-tree behind DBSCAN requires
the triangle inequality; someone expressed that as a type bound; the UI's option list narrowed.

That is the thesis in one example: a mathematical fact became a type constraint became a rendered
dropdown, with no restatement in between.

---

## Validation and parsing — why they cannot disagree

`validate_pipeline_schema` (`group_api/schema.jl:71-99`) builds one `JSONSchema.Schema` per card type
present and throws `SchemaValidationError(culprit, issue)`.

Parsing is `StructUtils.make(T, x, DashiStyle())`. `DashiStyle` reads **the same tags** —
`fieldtags`, `fielddefaults` — that `composite_schema` read. Schema and parser are two consumers of
one annotation, so they cannot describe different shapes. AgentGraph reported this as the property
that held up best in their port of the pattern.

---

## Where the projection leaks

Every finding in the briefs landed here. This is also the general truth about type-derived schemas.

### The type system cannot say it

- **Field order** is in the source but destroyed by the unordered `StringDict` it projects into.
  Measured on `GaussianEncodingCard`: declared `[method, input, n_components, lambda, suffix]`,
  emitted `["method", "suffix", "lambda", "input", "type", "n_components"]`.
- **Variant labels** have no slot. `OrderedDict{String, Type}` maps a key to a bare type, so
  `"kmeans"` has no display name anywhere. This is A3b.
- **Cross-field relationships.** `WeightedSqEuclideanMethod.weights` must match the card's `inputs`
  in length and order; nothing expresses it.
- **Positional meaning** is not only invisible but cannot be demoted to a validation error, because
  every ordering is valid and one is merely intended. It must be designed out (A5).

### Two projections of one type can disagree

The schema says `KMeansMethod.seed` is `{"minimum": 0, "type": "integer"}`; `StructUtils.lower`
writes `seed: null`. Both derived from the same struct and mutually contradictory. The guarantee is
that schema and *parser* agree — not that schema and *serialiser* do.

A related trap: `get_metadata` output is not a valid document. `inputs` comes back resolved
(`["PRES","TEMP"]`) rather than in document form (`{cols = [...]}`), because the group vocabulary is
resolved away by `Context` before any `Card` exists. **Round-tripping must read the stored JSON,
never reconstruct from `Card` objects.**

### The projection can be locally wrong and globally invisible

`schema_from_type` merges the tag into the derived schema, so a `JSON_VARIABLE`-tagged `String` field
emits `{"type": "string", "$ref": "#/$defs/variable"}`. Under a validator that discards `$ref`
siblings this is coherent; under one that applies them the field must be a string and an object at
once. Correct for years because only JSONSchema.jl ever read it. This is A3a.

---

## The general lesson

JSON Schema is excellent at **shape** — what fields exist, of what type, which are required, what
values are admissible — and silent about **presentation and relationships**. A type-derived schema
inherits exactly that split, because a type system is silent about the same things.

Derive everything derivable. Then be explicit that what remains is a *different kind of information*
rather than an oversight to be patched with extensions. Trying to carry order, labels and
discriminated lookup inside the schema is what pushed §13 toward `oneOf` and cost measurable error
quality — which is why the wire contract is now two artefacts from one traversal.
