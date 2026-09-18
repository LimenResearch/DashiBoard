# 10 — AgentGraph brief

Reconnaissance by the AgentGraph session. Read-only; nothing in this repository was modified.
Branch `ds-DashiUI` cut with `--no-track` from `main` at `ae27633`.

Every claim cites `agentgraph:path:LINE`. Anything not read directly from source is prefixed
`INFERRED:`. Where I contradict `01-decisions.md` I say so under a **⚠ Contradicts the spec**
heading and give the reason, as the protocol requires.

**Rebased 2026-09-01.** `ds-DashiUI` now sits on agentgraph `main` at `e9a59b5` (was
`ae27633`). Citations were re-checked against the new base: only `routes_executions.py` moved
(+3 lines, corrected here); `graph.py`'s anchors are unchanged and no other cited file was
touched.

**Read §11 first if you are deciding anything.** §1–§10 are written one-directionally — "this
was built here already, learn from it" — and that framing misled the reader three times. §11 is
the counterweight: where Pipelines is better than `core/schema/`, written with the DashiBoard
session and re-verified by me.

**Reading order if you are short on time.** §1.6 (what the derivation fails to express) and
§1.7 (verdict on decision §4) are the answer to "how did that go" — they are the most
transferable part of this document. §3.5 is the concrete thing that must be built for the UI to
save an artifact. §7.2 is the one place where AgentGraph is measurably *worse* than what
DashiBoard already has today, and you should not copy it.

---

## 0. Corrections to `02-stack.md` and `01-decisions.md`

Four factual corrections, all verified in source. None of them changes a decision; all of them
change a detail somebody would otherwise build against.

**0.1 — The `version` field is documented but never sent.** `02-stack.md` says "The envelope's
version field is `version`, not `jsonrpc`, documented in the client as a deliberate deviation."
The documentation is real (`agentgraph:src/agentgraph/tools/remote_procedure.py:21`) but the
client sends **no version field at all**. Every one of the three request builders emits exactly
`{id, method, params}`:
`agentgraph:src/agentgraph/tools/remote_procedure.py:359-363` (call),
`:408-412` (validate), `:438-440` (discover). A grep for `"version"` across the transport and
platform modules returns only that docstring line.

This works because ExperimentTracking's request struct defaults the field
(`ExperimentTracking.jl:src/api/json_rpc.jl:36`, `version::VersionNumber = v"2.0"`). So the
docstring is accurate advice about the field's *name* should anyone ever send it, and the wire
is currently version-free. If ExperimentTracking ever makes `version` required, AgentGraph
breaks silently and instantly.

**0.2 — `discover()` is not the only call AgentGraph makes on that connection.** Decision §9
says "The only call AgentGraph makes on that connection is `discover()`." That is true **of the
services API** (`agentgraph:src/agentgraph/api/routes_services.py:169-172` — `/health` is the
only route that dials the service) but not of AgentGraph as a whole. The tool layer, running in
the **taskiq worker process**, makes `train`, `evaluate` and `validate` calls over the same
resolved connection (`agentgraph:src/agentgraph/tools/remote_procedure.py:340-379`, `:387-428`;
method-name mapping `eval`→`evaluate` at `:381-385`).

The correct statement, and I think the one you meant: **the API process is a directory; the
worker process is the client.** Both resolve the same connection through the same function
(`resolve_connection`, `:157-170`), read fresh with no cache, which is what makes
`/v1/services/dashi/health` provably ping what a tool call would reach. The rest of §9 —
AgentGraph is not a proxy, an embedded UI's calls go browser → Julia directly — is confirmed
(§4 below).

**0.3 — Node types.** `02-stack.md` does not state these, but for the record the registered
types are `generative`, `agent`, `tool_node`, `function`, `router`
(`agentgraph:src/agentgraph/core/schema/node_specs.py:68-114`). The repository's own
`CLAUDE.md` still says "processor, agent, tool_node, router" — `processor` does not exist and
`function` is missing. A stale name in prose is harmless; the same staleness inside `derive.py`
was not, which is why `designer_param_refs` exists (§1.2).

**0.4 — `required_columns` is written by AgentGraph, not by a UI.** Decision §2 says "the UI
produces it by calling `validate` before saving". Today it is `dashiboard_validate` — an
AgentGraph *tool* — that computes `sorted(set(source_vars) - set(output_vars))` and annotates it
onto the config artifact (`agentgraph:src/agentgraph/tools/platform/spec.py:625-639`). The
decision is achievable but it is **not** achievable over HTTP as the API stands: there is no
route that writes `content_metadata`. See §3.5 — this is the single concrete API change the
refactor needs from me.

---

## 0.5 — AMENDMENT (added after the ExperimentTracking brief landed)

Three corrections to **my own §5**, all verified against `ExperimentTracking.jl` `main` after the
lead session flagged them. The first two are live defects in this repository, not documentation
slips — my §5 as originally written described a wire contract that does not work.

**0.5.1 — `dashiboard_validate` is broken against ET `main`, and it fails in the worst possible
way.** ET `main` serves exactly four methods — `train`, `evaluate`, `cards`, `schema`
(`ExperimentTracking.jl:src/api/handlers.jl:5-11`). There is **no `validate` method**.
Validation-without-execution is a **route**, not a method: `POST api/v1/probe`
(`src/api/router.jl:26-28`), implemented as
`probe_middleware(handler) = Returns(Returns(nothing)) ∘ handler` (`src/api/json_rpc.jl:160`) —
it runs the handler, which does all validation and returns a thunk, then throws the thunk away.

My client posts `{"method": "validate"}` to `api/v1`
(`agentgraph:src/agentgraph/tools/remote_procedure.py:410`). `get_method`
(`ET:src/api/json_rpc.jl:105-110`) does not find it and returns a `JSONFailure` with
`method_not_found` and the message `"Method validate not found"`. My client sees an `error` with
no `result` and raises `RemoteProcedureError` (`remote_procedure.py:422-427`) — and
`_build_validate_tool` **catches `RemoteProcedureError` and converts it to a finding**
(`agentgraph:src/agentgraph/tools/platform/spec.py:617-618`). So a drafting agent iterating
against `dashiboard_validate` receives:

```json
{"valid": false,
 "errors": "dashi.eval payload rejected by the service (code -32601): Method validate not found"}
```

**An absent capability arrives dressed as a content verdict.** That is exactly the distinction
`RemoteUnreachableError` exists to preserve (`remote_procedure.py:54-58`: *"nobody's verdict must
never look like one"*) — and this path defeats it, because method-not-found is a protocol-level
`JSONFailure`, indistinguishable at my parse site from a rejected payload. An agent told its
pipeline is invalid will rewrite a correct pipeline, forever.

**⚠ Retract from my §5.5:** the claim *"'validate accepts' and 'train would accept' are the same
statement by construction"* is currently **false** — nothing is validated at all. It becomes
true, and more strongly than I claimed, once the client uses `api/v1/probe` with the **real**
method name, because the probe route runs *literally the same handler* rather than a parallel
validator. **The probe-route design is better than the `validate` method I assumed and asked for
in §5.8; that ask is withdrawn in favour of it.** One validation path per method, present and
future, with nothing to drift.

Two notes for whoever fixes this on my side:

- `_method_name` (`remote_procedure.py:381-385`) must keep mapping `eval`→`evaluate`: the probe
  route dispatches on the same handler dict, so the method name still has to be a real one.
- The probe currently answers `{"id": …, "result": null}`. My `validate_remote` returns
  `data.get("result", {})` → `None`, and `spec.py:625` then calls `res.get("source_vars")` on it
  → `AttributeError`. **So the ET-side change making the probe thunk return
  `{source_vars, output_vars}` is a hard prerequisite, not an enhancement** — switching my client
  to the probe route without it trades a wrong answer for a crash.

**0.5.2 — `load_options` is silently dropped; the field is now `source_options`, inside
`DataFlow`.** `load_options` appears nowhere in ET `main`'s `src/`
(`git grep load_options main -- src/` → empty). `DataFlow` now carries `source_options`,
`destination_options` and `source_metadata` (`ExperimentTracking.jl:src/entries.jl:112-124`), and
`source_options` is what reaches the reader (`src/interface.jl:49`:
`kwargs = make(Dict{Symbol,Any}, flow.source_options)`).

My payload schema still declares a top-level `load_options`
(`agentgraph:src/agentgraph/tools/remote_procedure.py:259-263`). Because I flatten `DataFlow`
into `params` (`:355-358`) and ET reads `DataFlow(d)` and `Config(d)` from that same flat dict
(`ET:src/api/handlers.jl:18-20`), the flattening itself is correct and intentional on both sides
— but `make` ignores the unknown key. **A caller passing `nullstr` or `delim` has them dropped in
silence and gets a mis-parsed table, with no error anywhere.** The fix on my side is a rename plus
an added `destination_options`; the wire stays flat.

**0.5.3 — ET can already validate a pipeline against a declared column list, with no source file.
This changes decision §2's economics.** `DataFlow.source_metadata["cols"]` is documented in place
as *"a list of available column names… used to validate the pipeline"*
(`ET:src/entries.jl:121-122`), and `initialize_pipeline` uses it:

```julia
cols = get(flow.source_metadata, "cols", nothing)
return isnothing(cols) ? Pipeline(c.nodes, c.groups) : Pipeline(c.nodes, c.groups, cols)
```

(`ET:src/entries.jl:130-134`.)

So **§5.8's second ask — "validate without a source" — is largely already granted**, and I did
not know it when I wrote §5.8. A caller can hand ET a column *list* instead of a readable table
and have the pipeline checked against it. That is the missing half of decision §2: a UI can
validate and annotate a **source-agnostic** draft without a connected source, by passing the
column names it is authoring against. And on my side I already hold exactly that list —
`content_metadata["columns"]` on the source artifact, which my preflight reads today
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:40-44`).

`source` and `destination` are still non-`Optional` on `DataFlow` (`ET:src/entries.jl:113-115`),
so a fully source-free probe needs either placeholder paths or those fields relaxed. **That is a
question for the ExperimentTracking session, not an assertion from me.**


**0.5.4 — I cannot send `cols` at all, so nothing checks card-internal column references today.**
Added after the ExperimentTracking session's §4.3 reached me via the lead: `VariableConfig` treats
`nothing` as *unconstrained* rather than *empty*, so a caller that omits `cols` gets a pipeline
validated against no column list at all, and a card naming a nonexistent column passes validation
and fails only at SQL execution.

AgentGraph omits it structurally. My `DataFlow` declares six fields —
`id_var, source, destination, schema_, database, file_based`
(`agentgraph:src/agentgraph/tools/remote_procedure.py:196-230`) — with **no `source_metadata`**,
and `model_config = ConfigDict(extra="forbid")` (`:206`) means a caller cannot pass one either:
it fails client-side validation before the wire. `grep -rn source_metadata src/agentgraph/`
returns nothing. **So every dashi call AgentGraph has ever made validated with
`cols = nothing`.**

The compounding is the point. `docs/dashiboard.md`'s validation ladder assigns card-internal
column references to exactly one rung — *"the pipeline artifact's recorded requirements fit the
table: `required_columns ⊆ columns` — this covers card-internal references… fires only for
configs a prior `dashiboard_validate` annotated"*. All three of the mechanisms that were supposed
to cover this are broken or absent at once:

| mechanism | status |
|---|---|
| server-side validation against `cols` | never happens — I cannot send `source_metadata` (this item) |
| `required_columns` preflight | never fires — only `dashiboard_validate` writes it, and that tool calls a method ET does not serve (§0.5.1) |
| local preflight on `groups` | covers only single-item `{cols=[…]}` groups; silently skips lists and `nodes`/`groups` selectors (§5.6) |

So **card-internal column references are unchecked end to end**, and my brief's §5.5 "validation
ladder" overstated the coverage — I described the design, not the running system. The ladder's
fourth rung (`id_var`, `filters[].colname`, simple `groups[].cols`) does work; nothing below it
does.

Adding `source_metadata` to `DataFlow` and populating `cols` from the source artifact's
`content_metadata["columns"]` — which the preflight already reads
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:40-44`) — is ~6 lines and is the
cheapest of the four fixes. It is **recommendation #12** in §9.1, and unlike #9 it is not blocked
on anything: it needs no ET change, because ET already honours the field.

**0.5.5 — my #12 is blocked, and the two validators fail *differently*.** The lead session
relays from ExperimentTracking that the emitted card schemas rely on draft-07's
`$ref`-replaces-siblings rule, and that under 2020-12 (Ajv's default, so any browser validator)
every card field carrying a variable tag becomes unsatisfiable. **They verified the schema; I
verified the validator, and the two halves fail in opposite directions.**

`JSONSchema.jl` — the server-side validator Pipelines uses
(`DashiBoard:Pipelines/src/group_api/schema.jl:80-95`) — implements the draft-07 rule *literally*
(`~/.julia/packages/JSONSchema/qhs1I/src/validation.jl:100-111`):

```julia
function _resolve_refs(schema::AbstractDict, explored_refs = Any[schema])
    if !haskey(schema, "\$ref")
        return schema
    end
    schema = schema["\$ref"]          # the whole schema is REPLACED; siblings discarded
    ...
```

So the failure modes are not the same failure seen twice:

| validator | `$ref` semantics | what happens |
|---|---|---|
| JSONSchema.jl (server) | draft-07 — replaces siblings | sibling constraints **silently ignored**; validation runs and checks *less than the schema appears to say* |
| Ajv 2020-12 (browser) | annotation *alongside* siblings | both apply; contradictory siblings make the subschema **unsatisfiable** |

That distinction matters for the fix: a server that silently under-checks and a browser that
rejects everything need different remedies, and only the browser half announces itself.

**RESOLVED — #12 is unblocked.** The lead answered the enum-placement question and I verified
each citation in `Pipelines/` myself:

- `JSON_VARIABLE = json_config(var"$ref" = "#/$defs/variable")` — a **bare `$ref`, nothing else**
  (`DashiBoard:Pipelines/src/structs/card_schema.jl:61`).
- The enums live on the **targets**: flat dialect `variable_schema = json_string(enum = variables)`
  (`card_schema.jl:28`); group dialect `node`/`group`/`col` are `json_string(enum = …)` reached
  transitively through `variable_item_schema`'s properties
  (`Pipelines/src/group_api/schema.jl:14-19, :28-47`).

So draft-07 resolution discards only what `schema_from_type` derived and merged as siblings —
`{"type": …}` and, where a Julia default exists, `"default"`
(`Pipelines/src/structs/json_schema.jl:23-31`: `schema["default"] = …` then
`merge!(schema, config)`). **The substantive column constraint is on the target and survives.
Sending `cols` therefore buys real server-side checking.**

Two refinements I owe back, from reading that merge:

1. **It is `type` AND `default`, not `type` alone — but far narrower than I first claimed.**
   Both are set before `merge!`, so both are siblings. My first version said "at least a dozen
   tagged fields" and listed every `partition::Union{String,Nothing} = nothing`. **That was
   wrong**, and the line I had already quoted says why: the write is guarded,
   `isnothing(default) || (schema["default"] = …)` (`json_schema.jl:27`), so a `= nothing`
   default emits no `default` key at all. I pasted the guard and then reasoned past it.
   Verified: **exactly five** fields carry a discardable default, all
   `= String[] & (dashi = JSON_VARIABLES,)` — `rescale.jl:111`, `:113`, `window_function.jl:28`,
   `split.jl:54`, `:55`. The dialects do disagree about defaults, on those five.
2. **The browser unsatisfiability is specific to the GROUP dialect — and NOT to 2020-12.**
   The dialect half holds: under the flat dialect `variable` is `json_string(enum=…)`, the
   derived `{"type":"string"}` sibling agrees, and nothing shows; under the group dialect
   `variable` resolves to an object/array (`one_or_many_schema(variable_item_schema(...))`,
   `group_api/schema.jl:33`) while `schema_from_type` still derives `String`, so the field must
   be a string and an object at once. That ties A3a to decision §12's schema-dialect gap, and
   the two now ship together.

   **The draft half was wrong, and the correction matters more than the claim did.** I said
   this was 2020-12 behaviour that draft-07 would avoid. The lead ran the fixture (Ajv 8.20)
   and measured **identical results across both drafts** — `$ref` + `type:string` sibling is
   INVALID under draft-07 *and* 2020-12, because Ajv 7+ applies `$ref` siblings regardless of
   the declared draft. The only thing hiding this today is JSONSchema.jl implementing the
   literal replace rule. **So pinning `$schema` to draft-07 would not have fixed it** — it
   would have produced a schema the Julia server accepts and every modern browser validator
   rejects, while looking settled. A3a was reworded from "pin the draft, and stop emitting the
   sibling" to "stop emitting `type`/`default` siblings; pin as well", with the measurement
   recorded. **My reasoning-from-source produced a plausible wrong answer that a five-line
   fixture caught** — which is the case for executing rather than reading, made against me.

*(Provenance: `_resolve_refs` and every `Pipelines/` citation above are read-from-source by me.
Nothing here was executed — the Pipelines environment is not instantiated on this machine, and
the lead reports the same. The Ajv/2020-12 behaviour is relayed and reasoned-through, not
observed.)*

**0.5.7 — my §7.2 recommendation 3 was wrong, I never tested it, and the lead's explanation of
why is also wrong.** The lead measured `oneOf` vs gated `allOf`+`if`/`then` in Ajv and found
`oneOf` is the one that reports from every branch — the reverse of what I claimed. They
hypothesised my symptom came from `derive.py` lacking the discriminator gate that Pipelines'
`tagged_schema` emits, and asked me to check rather than take it.

**I checked. I have the gate** — `derive.py:283-292` puts `required: ["id","type"]` and
`properties: {type: {enum: [...]}}` at the item level, *above* the `allOf` of `{if, then}`. So
their hypothesis does not explain it. I then ran the thing I should have run in the first place,
against my own real designer schema (`Draft202012Validator`, jsonschema):

| case | errors |
|---|---|
| bogus type `"nope"` | **1** — `/nodes/0/type` `enum: 'nope' is not one of ['agent','function','generative','router']` |
| `type: function`, `registry_key` not in the enum | **1** — `/nodes/0/parameters/registry_key` `enum: … is not one of ['dashiboard_eval','dashiboard_train']` |
| `type: function` declaring `tools` (the `maxItems: 0` fence) | **1** — `/nodes/0/tools` `maxItems` |

**One clean, correctly-pathed error every time.** The gated `allOf` + `if`/`then` shape is
*good*, and §7.2 recommendation 3 is withdrawn.

**What I actually saw, and mislabelled.** The bad message I quoted in §1.6 —
*"is not valid under any of the given schemas"* — is `anyOf`, from the `Optional[T]` nullable
wrapper, not the union composition:

```
path      : /nodes/0/parameters/model_name
validator : anyOf
schema    : {"anyOf": [{"$ref": "#/$defs/model_id"}, {"type": "null"}]}
```

I had one piece of real evidence, attributed it to the wrong mechanism, and wrote a
recommendation that would have made things worse. §1.6's `anyOf` finding and §14 rule 2 are the
correct reading of that same evidence; rule 3 was the same observation misdiagnosed.

**And a new finding from the run, worth more than the retraction.** The enum listing is not lost
— it survives as sub-errors on the `anyOf`:

```
context : ["enum: 'bogus-model' is not one of ['us.anthropic.claude-sonne…",
           "type: 'bogus-model' is not of type 'null'"]
```

So the `anyOf` message is partly a **rendering** failure, not only a schema-shape one: any
validator exposing sub-errors (jsonschema's `e.context`, Ajv's nested errors) still has the
real reason. Rendering the first non-`null` sub-error recovers it **with no schema change**.
That is §7.2's new recommendation 2b, and it applies to DashiBoard's error contract too.

*(Provenance: everything in this item is EXECUTED — the three-case table and the `anyOf`
breakdown were run against the real derived schema in this session. The Ajv figures are the
lead's, relayed.)*

**0.5.8 — the leaf-vs-composition rule generalizes, but its offenders are validator-specific.**
The lead verified 2b on Ajv and found it stronger there than I reported: `params.allowedValues`
carries the enum as **structured data**, not inside a message string. They then generalized it
past `anyOf` — the same one-leaf-plus-one-empty-summary pattern appears in the `if`/`then` union,
where `if: must match "then" schema` carries nothing — and made it their rule A7: *surface leaf
errors, never composition keywords.*

I ran it against my own schema before adopting it, because the generalization implies my
`if`/`then` union leaks a summary too. **It does not** — the offenders differ by validator:

| composition site | Python `jsonschema` | Ajv 8 |
|---|---|---|
| `anyOf` nullable wrapper | **leaks** — top-level error is `validator="anyOf"`, leaves in `e.context` | leaks |
| `if`/`then` variant union | **never surfaces** — a bad value inside a variant arrives as a bare leaf (`enum` at the right path) | emits `if: must match "then" schema` alongside the leaf |

So A7 is right and I have adopted it, but the *list* of keywords to discard is not portable.
On my side the whole win comes from `anyOf`; my three-case union table in §0.5.7 was already
clean because `if` never leaked here in the first place. **Anyone applying A7 should measure
their own validator rather than copying either of our lists.**

The structured-data half holds on my side too: `leaf.validator_value` returns the enum as a real
`list` (verified), the direct equivalent of Ajv's `params.allowedValues`. So the "render choices,
not prose" outcome is available in both stacks.

*(Provenance: every row of the table above and the `validator_value` check were EXECUTED in this
session against the real derived schema. The Ajv column is the lead's, relayed.)*

**0.5.6 — do NOT retire the client-side preflight once #12 lands. It is the only coverage of
two paths, and #12 will look like a reason to remove it.** From the ExperimentTracking session's
*executed* run, relayed by the lead: supplying `cols` converts ACCEPT into REJECT for bad columns
in card `inputs`, card `group_by`, and group definitions — so #12 is confirmed **behaviourally**,
not merely structurally. But two paths stay uncovered server-side, with or without `cols`:

| path | server coverage after #12 | only coverage |
|---|---|---|
| a filter naming a nonexistent column | none — until a filter schema lands | my `_dashi_preflight` `filters[i].colname` check (`dashiboard.py:64-66`) |
| `id_var` not among the source columns | **none, even after a filter schema** | my `_dashi_preflight` `id_var` check (`dashiboard.py:63`) |

"The server does real column checking now" is the natural reason to delete a client-side
duplicate, and here it would silently remove the last check on both. **My recommendation #3
(generalize the preflight) must not turn into "replace the preflight".** The `id_var` check in
particular has no server-side successor planned at all.

**Consequence for my §9 table:** items 1–8 stand unchanged; four client-side fixes join them in
§9.1.

---

## 1. The schema layer

`core/schema/` is four files, 960 lines total: `node_specs.py` (the registry), `params.py` (the
typed models), `derive.py` (composition + context injection), `contracts.py` (structured-output
contracts). The docstring stating the lineage is
`agentgraph:src/agentgraph/core/schema/__init__.py:1-7`; `derive.py` names its model explicitly
at `agentgraph:src/agentgraph/core/schema/derive.py:4` — *"Mirrors Pipelines'
`options_schema`/`conditional_options_schema`"*.

### 1.1 How a node type registers

`NodeSpec` is a frozen dataclass (`node_specs.py:19-40`) carrying: `type_key`, a `params_model`
(a pydantic `BaseModel` subclass or `None`), a human `label`, a dotted `runtime_class_path`, a
`designer_facing` flag, and `designer_param_refs`. `NODE_SPECS` is a plain module-level dict
(`:43`) and `register_node_spec` is a one-line setter (`:46-47`). Registration happens at import
by five literal calls (`:68-114`).

Two consumers derive from that one dict:

- **the runtime**, via `runtime_node_class_map()` (`:54-65`), which imports each
  `runtime_class_path` and returns `{type_key: class}`. `router` declares `None` and is built by
  a factory instead (`:112`).
- **the schema**, via `derive.py`.

`designer_facing=False` on `tool_node` (`:90`) is the one flag that makes a type real at runtime
but invisible to the author: `<agent>__tools` nodes are created by inference, and a
hand-declared one is inert.

This is the part that worked cleanly. Adding a node type is one dataclass literal, and both
the schema and the builder pick it up with no other edit. **I would recommend the shape
unreservedly.**

### 1.2 The `designer_param_refs` scar — read this one

`NodeSpec.designer_param_refs` (`node_specs.py:32-40`) is a per-spec map `{param_name:
defs_name}` telling `derive.py` to replace a parameter's schema with a `$ref` to a contextual
enum. Its docstring ends: *"Declared here, per spec, so derive.py carries no type_key literals."*

The history behind that sentence, from the comment at `derive.py:204-206`: the fence used to be
written in `derive.py` as `if type_key == "<literal>"`. A node type got **renamed**, the literal
did not, and the check **silently stopped enforcing** — no error, no test failure, just a
security fence that had quietly become a no-op. The fix was to move the coupling onto the spec,
where a rename cannot outlive it.

This is the single most transferable lesson in this brief for `CARD_SPECS`. **Any rule keyed by
a type name must live on that type's spec, never in the deriver.** A deriver holding a literal
type name is a fence that will silently fall over on the next rename. `derive.py` still holds
two such literals — `if type_key not in ("agent", "tool_node")` (`:171`) and `if type_key !=
"agent"` (`:180`) — which is the same latent bug, unmigrated.

### 1.3 `SchemaContext` — how enums are injected

`SchemaContext` (`derive.py:19-56`) is a dataclass of **zero-argument callables**, one per enum
category: `tool_keys`, `python_tool_keys`, `skill_keys`, `model_ids`, `regions`, plus a free-form
`extra_defs` dict. `build_defs()` (`:31-56`) calls each, sorts and dedupes, and emits
`{"type": "string", "enum": [...]}` under a `$defs` name. **An empty or `None` result means "do
not constrain"** (`:22`) — a deliberate fail-soft.

`default_schema_context()` (`:59-112`) wires them to the live sources: the tool registry, the
Dolt reviewed-tool rows, the reviewed-skill rows, the Bedrock model catalog, the catalog's
discovered regions.

Two design notes worth carrying:

- **The enum is applied conditionally, not unconditionally.** `_apply_context` (`:120-144`)
  wraps model/region constraints in an `if/then` keyed on `model_provider == "bedrock_converse"`
  (`CATALOG_PROVIDER`, `:117`), so an ollama graph keeps free-form model names. Pipelines'
  `conditional_options_schema` is the same idea.
- **`extra_defs` is dead.** Declared at `:29`, read at `:32`, and passed by **no caller in the
  repository** — grep returns those two lines only. The extension seam nobody needed. Do not
  build the equivalent until something asks for it.

**The categorical limitation, and it matters for you.** Every provider in `SchemaContext` is an
*environment* enum: global, document-independent, the same for every graph on the deployment.
There is **no provider for document-derived enums** — nothing injects the set of node ids, or
the set of output names a given node declares, into the schema. Decision §3 requires exactly
that ("Dynamic enums are baked server-side… `card_schema(key, variable_config)`"). Pipelines'
`VariableConfig` is *document*-scoped; AgentGraph's `SchemaContext` is *deployment*-scoped.
`02-stack.md` calls `SchemaContext` "`VariableConfig` by another name" — they are the same
mechanism but not the same scope, and the scope is the harder half.

Consequence for AgentGraph: the input reference `from: node_id.output_name` is expressed in the
schema as a **regex** (`agentgraph:src/agentgraph/core/types.py:19`) and nothing more. Whether
the node exists, and whether it declares that output, is checked in the loader
(`auto_inherit.py:83-89`) with a runtime `ValueError`. A UI form built from that schema cannot
offer a dropdown of valid sources — it can only offer a text box and wait to be told it was
wrong. **You are attempting the harder and better version of this. I did not build it, and its
absence is the largest single reason our schema cannot drive a good form.**

### 1.4 How `derive.py` composes the union

`node_schema(type_key, ctx, audience)` (`derive.py:147-244`) builds one variant:

1. deep-copy `NodeConfig.model_json_schema()` — the **common** node shape (`:165`);
2. pin `properties.type` to `{"const": type_key}` (`:167`);
3. structurally fence `tools` and `skills` to agent-ish types by overwriting them with
   `{"type": "array", "maxItems": 0, "description": …}` (`:171-185`);
4. splice the spec's params-model schema into `properties.parameters`, after `_apply_context`
   and (for the designer) the tightening at `:194-209`;
5. inline the params model's nested `$defs` into the variant's (`:211-212`);
6. merge the context `$defs`, constrain `tools[].registry_key` to `tool_key` (`:221-228`) and,
   designer-only, `skills[]` to `skill_key` (`:234-241`);
7. title it `f"{spec.label}NodeConfig"` (`:243`).

`graph_config_schema(ctx, audience)` (`:247-329`) then composes them: filter to
`designer_facing` types for the designer audience (`:264-266`), build each variant, hoist its
`$defs` up to the root, store it as `$defs/{type_key}_node`, and emit one `if/then` per type
into an `allOf` (`:276-281`). The result replaces `properties.nodes`:

```json
"nodes": {
  "type": "array", "minItems": 1,
  "items": {
    "type": "object",
    "required": ["id", "type"],
    "properties": {"type": {"enum": ["agent","function","generative","router"]}},
    "allOf": [
      {"if": {"properties":{"type":{"const":"generative"}},"required":["type"]},
       "then": {"$ref":"#/$defs/generative_node"}},
      {"if": {"properties":{"type":{"const":"agent"}},"required":["type"]},
       "then": {"$ref":"#/$defs/agent_node"}},
      {"if": {"properties":{"type":{"const":"function"}},"required":["type"]},
       "then": {"$ref":"#/$defs/function_node"}},
      {"if": {"properties":{"type":{"const":"router"}},"required":["type"]},
       "then": {"$ref":"#/$defs/router_node"}}
    ]
  }
}
```

That is verbatim from a real generation (see §1.5 for how). Note it is `allOf` + `if/then`, not
`oneOf` with a `discriminator`. **That choice cost us error quality** — see §7.2.

### 1.5 `GET /v1/graphs/schema`, with a real example

The route is four lines (`agentgraph:src/agentgraph/api/routes_graphs.py:33-40`):

```python
@router.get("/schema")
async def get_graph_schema() -> dict:
    from agentgraph.core.schema.derive import default_schema_context, graph_config_schema
    return graph_config_schema(default_schema_context(), audience="designer")
```

I generated the real output with a synthetic context (two tools, two python tools, one model id,
two regions) so this brief is reproducible without live AWS:

```python
graph_config_schema(SchemaContext(
    tool_keys=lambda: ['web_search','dashiboard_train'],
    python_tool_keys=lambda: ['dashiboard_train','dashiboard_eval'],
    model_ids=lambda: ['us.anthropic.claude-sonnet-4-20250514-v1:0'],
    regions=lambda: ['us-east-1','eu-west-1'],
), audience='designer')
```

**25 249 bytes**, 22 `$defs`: `ArtifactOutputSpec, CheckpointerConfigModel, ConversationConfig,
EdgeConfig, HeadroomConfig, HeadroomVar, InputConfig, McpParams, McpServerConfig,
ModelExtraParams, NodeConfig, OutputConfig, RetryConfig, ToolConfig, agent_node, function_node,
generative_node, model_id, python_tool_key, region, router_node, tool_key`. With a live Bedrock
catalog the `model_id` enum alone is dozens of entries, so the real payload is larger.

Here is `$defs/function_node` — the smallest variant, and the most instructive:

```json
{
  "title": "FunctionNodeConfig",
  "type": "object",
  "required": ["id", "type"],
  "properties": {
    "id":   {"title": "Id", "type": "string"},
    "type": {"const": "function"},
    "name": {"anyOf": [{"type":"string"},{"type":"null"}], "default": null, "title": "Name"},
    "timeout": {"default": 30.0, "title": "Timeout", "type": "number"},
    "parameters": {
      "title": "FunctionParams",
      "type": "object",
      "additionalProperties": false,
      "required": ["registry_key"],
      "properties": {"registry_key": {"$ref": "#/$defs/python_tool_key"}},
      "allOf": [
        {"if":   {"properties": {"model_provider": {"const": "bedrock_converse"}},
                  "required": ["model_provider"]},
         "then": {"properties": {"model_extra_params": {"properties": {
                    "region_name": {"anyOf":[{"$ref":"#/$defs/region"},{"type":"null"}]}}}}}}
      ]
    },
    "defer":   {"default": false, "title": "Defer", "type": "boolean"},
    "inputs":  {"items": {"$ref": "#/$defs/InputConfig"},  "title": "Inputs",  "type": "array"},
    "outputs": {"items": {"$ref": "#/$defs/OutputConfig"}, "title": "Outputs", "type": "array"},
    "template_variables": {"items": {"type":"string"}, "title": "Template Variables", "type": "array"},
    "prompt_template": {"anyOf":[{"type":"string"},{"type":"null"}], "default": null,
                        "title": "Prompt Template"},
    "tools":  {"type":"array","maxItems":0,"description":"Tools can only be attached to agent nodes."},
    "aliases":{"additionalProperties":{"items":{"type":"string"},"type":"array"},
               "title":"Aliases","type":"object"},
    "headroom":{"anyOf":[{"$ref":"#/$defs/HeadroomConfig"},{"type":"null"}],"default":null},
    "mcp":     {"anyOf":[{"$ref":"#/$defs/McpParams"},{"type":"null"}],"default":null},
    "skills": {"type":"array","maxItems":0,"description":"Skills can only be attached to agent nodes."}
  }
}
```

Look at what a UI would have to render from that. A function node — a deterministic call to one
Python tool — is offered a `prompt_template`, `template_variables`, a `headroom` compression
block and a **whole MCP server configuration**, because every variant starts from
`NodeConfig.model_json_schema()` and only `tools`/`skills` were ever fenced. And that `allOf`
block inside `parameters` is **dead schema**: `_apply_context` (`:129-134`) adds the region
constraint whenever `"region" in defs`, without first checking that the params model has a
`model_extra_params` field at all — `FunctionParams` (`params.py:59-68`) has exactly one field.
Combined with `additionalProperties: false` (`:195`), the `if` can never fire. It is inert
rather than harmful, but it is 15 lines of noise in every function node's schema, and any
generic form renderer will try to do something with it.

### 1.6 What worked, what hurt, and what the derivation cannot express

**Worked.**

- *One dict, two consumers.* `NODE_SPECS` driving both `runtime_node_class_map()` and the schema
  means "the type exists" and "the type is describable" cannot diverge.
- *Validation and schema from the same models.* `validate_params_for_type`
  (`params.py:221-235`) validates the parameters dict against the same `params_model` the
  schema is generated from. This is the promise in the module docstring — *"schema and
  validation cannot drift"* (`params.py:6-7`) — and it holds.
- *Audiences.* One derivation, two strictnesses, chosen by an `audience` string. The designer
  gets `additionalProperties: false` and fenced enums; runtime stays permissive so
  inference-created nodes validate. Cheap, and it earned its keep.
- *Conditional context injection.* Constraining model ids only under the catalog provider means
  adding a provider does not require touching the schema.
- *Fail-soft enums, fail-closed gate.* An empty enum does not constrain (`derive.py:22`); but
  the registry's `valid` gate **refuses the write** if the context cannot be built at all
  (`agentgraph:src/agentgraph/core/dolt/registry.py:120-127`). Soft where a partial answer is
  useful, hard where a missing answer would admit garbage. I would keep exactly this split.

**Hurt.**

- *`Optional[T]` becomes `anyOf: [T, null]`, and that destroys the error message.* Validating a
  real seeded config against the designer schema, the model-id violation reports:

  ```
  nodes/0/parameters/model_name: 'eu.amazon.nova-2-lite-v1:0' is not valid under any of the given schemas
  ```

  It does not say "not in the catalog". It does not list the catalog. It does not name which
  branch of the `anyOf` was meant. Every optional enum-constrained field in the schema produces
  this message. **If you make nullable fields `anyOf`-wrapped and rely on JSON Schema errors as
  your UI error contract (decision §3), you will inherit this exactly.** Mitigation: attach a
  `title`/`description` to the *wrapper*, or use `["string","null"]` type arrays with the enum
  on the same level, so the failing keyword is `enum` and the message names the options.

- *Injecting an enum by replacing a property destroys its presentation metadata.* Measured on
  the real designer schema:

  | field | title | description |
  |---|---|---|
  | `parameters.model_name` | `"Model Name"` | present |
  | `parameters.model_provider` | **`None`** | **empty** |
  | `parameters.registry_key` (function) | **`None`** | **empty** |
  | `parameters.temperature` | `"Temperature"` | empty |

  `model_provider` and `registry_key` both carry a `description` on their pydantic Field
  (`params.py:37-39`, `:65-68`) and lose it because the designer pass **overwrites** the property
  wholesale — `{"const": CATALOG_PROVIDER}` at `derive.py:197`, `{"$ref": …}` at `:209`. A form
  built from this schema shows a bare unlabeled control for the one field whose meaning most
  needs explaining. **This is a direct hazard for decision §4** and the fix is one line: merge
  the injected constraint into the existing property dict instead of replacing it.

- *`title` is pydantic's autogenerated field name, not authored prose.* `"Id"`, `"Max Tool
  Iterations"`, `"Prompt Template"` — those are `str.title()`-ish transformations of the Python
  identifier, not labels anyone wrote. They are *adequate* (they read fine) precisely because
  the Python names are good. Where a name is bad, the label is bad, and there is no way to fix
  the label without renaming the field.

- *The bipartite `allOf` + `if/then` union produces bad errors.* See §7.2.

**What the derivation cannot express at all.** Four, in ascending order of how much they hurt:

1. **Node-level extra keys.** `additionalProperties: false` is applied to `parameters` only
   (`derive.py:195`), never to the node object. A node key that does not exist is accepted by
   the schema **and silently dropped by pydantic** (`NodeConfig` has no `model_config`, so
   `extra="ignore"`). Verified:
   ```
   NodeConfig(id='x', type='agent', max_tool_iterations=2).model_extra  ->  None
   Draft202012Validator(designer_schema).iter_errors(
       {'id':'t','nodes':[{'id':'a','type':'agent','totally_bogus_key':1}]})  ->  []
   ```
   And this is not hypothetical: **six seeded configs** put `max_tool_iterations` at the node
   level where it belongs under `parameters` — `array_summary_statistics.yaml:20`,
   `max_value_finder_graph.yaml`, `warehouse_management_agent.yaml`,
   `mdd_meta_analysis_system.yaml`, `statistical_comparison_ab_test.yaml`, `stk_manager.yaml`.
   All six have been silently ignoring that setting, through a schema layer whose entire point
   is to make that impossible. **Lesson: derive strictness, not only shape. `extra="forbid"` on
   the authored models, and `additionalProperties: false` at every authored level.**

2. **Cross-node references.** `from: node_id.output_name` is a regex (`types.py:19`);
   `feeds_back_to: 'node_id.input_name'` (`types.py:110-111`) is not even that. Both are checked
   in the loader with a `ValueError`. This is the §1.3 scope gap.

3. **Positional semantics.** An agent's auto-injected finish tool is named after its **first
   declared output**: `custom_outputs[0]` at
   `agentgraph:src/agentgraph/nodes/agent_node.py:109` and `:162`. Nothing in the schema marks
   index 0 as special — `outputs` is a plain `array` of `OutputConfig`. A UI that renders it as a
   drag-reorderable repeater lets a user rename the finish tool by dragging, invalidating every
   prompt that says "call the `X` tool" (the house convention). **If any of your card fields
   carry positional meaning, the schema will not tell the UI, and reordering is exactly what a
   generic array widget offers.**

4. **Per-type field applicability.** Only `tools` and `skills` are fenced, by two hand-written
   type literals (`derive.py:171`, `:180`). Everything else on `NodeConfig` appears on every
   variant. Ironically the fix already exists in the same file: `designer_param_refs` proved the
   pattern, and nobody generalized it to a `designer_field_fences` on `NodeSpec`.

**Workarounds we actually shipped for these.** (1) is not worked around — it is an open defect I
am flagging here. (2) is worked around by loader-raised `ValueError`s with deliberately
constructed messages: `auto_inherit.py:79-89` names the consumer node, the ghost reference, and
the producer's real outputs. (3) is worked around by prose convention in prompts and by the
finish-call interceptor enforcing output presence with two forced retries. (4) is worked around
by the `maxItems: 0` trick for two fields and not at all for the rest.

### 1.7 Would decision §4 have been enough for us?

**Yes for labels and ordering; no for one class of field, and there is a trap in the mechanism.**

Taking §4's three parts separately:

- **Label from `title`, help from `description`, order from struct field order.** Adequate.
  Field order is what pydantic emits and it is the order we want. Autogenerated titles read
  fine. I would not have wanted a sidecar.

- **Widget kind inferred from JSON type plus constraints.** Adequate for the leaves —
  enum→select, bounded number→spinner, boolean→toggle all fall out. It breaks on exactly one
  shape in our schema, and it is a shape you also have: **a free-form `dict`**.
  `NodeConfig.aliases` derives to `{"additionalProperties": {"items":{"type":"string"},
  "type":"array"}, "type":"object"}` and `groups` in the dashi payload derives to
  `{"type":"object", "additionalProperties": true}`
  (`agentgraph:src/agentgraph/tools/remote_procedure.py:254-258`). No inference rule turns
  "object with additionalProperties" into a usable widget — it is a key/value repeater whose
  value editor depends on what the map is *for*, and the type does not say. **Your `groups`
  (`{name: {cols|nodes|groups, through}}`) is precisely this shape**, and decision §6 already
  concedes it needs a purpose-built picker rather than an inferred widget. That is the right
  call; just be aware that "no override" and "one bespoke component for the variable picker"
  have to coexist, and the schema needs *something* — a `$ref` to a named `$def`, most likely —
  for the renderer to dispatch on. A `$ref` name is not a widget override; it is type identity,
  which §3 already says is what components dispatch on. I think you are fine, but the seam
  should be deliberate rather than discovered.

- **"There is deliberately no override."** I agree, and our experience supports it: our sidecar
  is the *audience* mechanism, not a per-field one, and a per-field escape hatch would have
  metastasized. But **the no-override rule is only safe if injection preserves metadata.** Our
  fences replace properties and drop `title`/`description` (measured above), so we currently have
  fields with no override *and* no label. If DashiBoard bakes dynamic enums into `$defs` by
  replacing a property schema, decision §4's contract quietly fails for exactly the fields
  decision §3 cares most about. **Merge, never replace.** That is the one-sentence version of
  everything I learned here.

---

## 2. Nesting depth

**How deep our schemas actually nest: three object levels, and not by design.** Measured on the
generated designer schema by walking `$ref` edges:

```
agent_node    -> depth 3, refs: HeadroomConfig, InputConfig, McpParams,
                              ModelExtraParams, OutputConfig, ToolConfig, model_id, region
function_node -> depth 3
router_node   -> depth 3
McpParams     -> McpServerConfig            (node -> mcp -> servers[] -> leaf fields)
OutputConfig  -> ArtifactOutputSpec         (node -> outputs[] -> artifact -> leaf fields)
HeadroomConfig-> HeadroomVar
```

The deepest real path is `node → mcp → servers[] → headers{}` — an object, inside an array,
inside an object, inside the node — which is your three-to-four levels. So **yes, our schemas
nest that far, and the pure-recursive rendering you describe would work on them.** Every one of
those `$def`s is renderable from its own type: `McpServerConfig` (`params.py:84-187`) knows its
own `url`, `registry_key`, `headers`, `timeout` and needs nothing from the node above it.

**But our nesting is compositional, not variant-selecting.** This is the honest structural
difference and it matters for you. We have no equivalent of `ClusterCard{M <: ClusteringMethod}`
→ `KMeansMethod{D <: DissimilarityMethod}` → `WeightedMinkowskiMethod`. Our discriminated union
exists at exactly **one** level — the node type — and below it everything is fixed structure.
Your abstract-union-typed *field* rendering as a type selector plus the selected variant's
component, recursively, at arbitrary depth, is strictly more than we built. **I cannot report
that it works, because we never tried it.** What I can report is that our single-level union
was mechanically simple and gave poor errors (§7.2), and error quality degrades with the number
of union branches a validator has to consider — so the thing I would watch closely at three
levels of nested unions is *diagnostics*, not rendering.

### 2.1 Cases where a nested field needed something from an ancestor

We hit this four times. In ascending order of how well it went:

**(a) `model_name` needs `model_provider` — a SIBLING, one level up.** The model-id enum is only
meaningful for the catalog provider. **Solution: JSON Schema `if/then`** at
`derive.py:136-144` — `if properties.model_provider const bedrock_converse, then model_name
$ref model_id`. This worked well. `if/then` on a shared parent is the clean expression of a
sibling constraint and it costs no ambient scope: the *renderer* still needs nothing, and the
*validator* handles the coupling. **Recommendation: this is the tool for your
`DBSCANMethod{D <: MetricMethod}`-style narrowing when it cannot be expressed as a type bound.**
(Your type bounds are better — they narrow the *options list*, which `if/then` cannot do.)

**(b) `LLMParams.provider_requires_model`.** Same coupling, expressed a second time, as a
pydantic `@model_validator` (`params.py:50-56`). Two encodings of one rule, in two languages,
that nothing checks against each other. Not a bug today; a drift waiting to happen. **If a rule
is expressible in the schema, express it only there.**

**(c) `McpParams.reject_legacy_top_level_fields`** (`params.py:209-218`) — a *child* rejecting
keys that used to live on it and now belong on its grandchildren
(`servers[].allowed_tools`). This is an ancestor/descendant migration constraint. It is a
runtime validator raising a prose error; the schema says nothing. It works, and it is the right
place for it, because it is a *transitional* rule about a shape that no longer exists.

**(d) The finish-tool name, `outputs[0]`** (`agent_node.py:109`, `:162`). A node-level behaviour
determined by a leaf's *position*. This one went badly and stayed badly. It is invisible in the
schema, invisible in the form, and the only reason it does not bite constantly is that a graph's
outputs are usually written once and never reordered.

**Verdict on decision §3's "cross-level constraints are validation, not rendering".** I endorse
it, with one amendment drawn from (d): **the demotion is only safe when the constraint is about
a field's *value*.** `weights` must match `inputs` in length is a value constraint and demotes
cleanly to a `SchemaValidationError`. A constraint about a field's *position or identity* — "the
first output names the finish tool" — does not demote, because there is no invalid value to
report; every ordering is valid and one of them is merely surprising. If any DashiBoard card has
a rule of that shape, it needs to be designed out, not demoted.

---

## 3. The config artifact lifecycle

### 3.1 Creation and registration

Two entry points into the store, both in
`agentgraph:src/agentgraph/tools/artifact_store.py`:

- **`save(key, data, artifact_type, description, …)`** (`:325-441`) — the value path. Resolves a
  codec from `(artifact_type, artifact_format)`, mints a uuid7, writes to
  `ARTIFACT_ROOT/<uuid7>/<alias><suffix>`, then creates the registry row. **File first, then
  row** (`:392-393`): a row pointing at nothing is worse than unindexed bytes.
- **`register_file(artifact_id=None, alias, path, artifact_type, description, …)`**
  (`:552-650`) — the index-in-place path, for a file some other process wrote. No copy; the row
  points at `path` wherever it is. Raises if the file is absent (`:590-594`).

Both funnel into `_build_index_element` (`:258-322`), which stamps the `ArtifactElement`:
`id`, `alias`, `version`, `description`, `data_lineage`, `artifact_type`, `storage_location`,
`path`, `content_metadata`, `storage_metadata`, `format`, `size_bytes`, `origin`,
`analysis_lineage`, `organization_id`, `team_id`.

**Versioning.** `_next_version(alias)` (`:732-752`) lists the alias's existing rows and returns
`1.0.{max_patch+1}`, or `1.0.0` for the first. The uniqueness constraint is
`(org, team, alias, version)`. A row with `alias=None` is *standalone* and carries **its own
uuid as the version string** (`:774-778`) to satisfy a NULLS-NOT-DISTINCT constraint.

**Immutability.** Artifacts are never repointed (`:652-657`: "a row is never repointed, only
created or removed"). Iterating on a config means **saving a new version under the same alias**;
pinning the uuid freezes it forever (`docs/dashiboard.md:247-249`).

### 3.2 uuid-versus-alias resolution

`_fetch_entry(ref)` (`artifact_store.py:817-853`) is the resolver, and it is a **three-way
discrimination on the string**:

1. `_is_uuid(ref)` (`:165`) → `registry.read_entry(ref)`, one immutable row, no version logic.
2. `"@" in ref` → **`rpartition("@")`**, deliberately the *last* `@` (`:836-838`: "an alias may
   itself contain `@`, a version never does"), then `resolve_alias_version(name, ver)`. If that
   misses it **falls through** to (3), because the whole string may itself be an alias
   containing `@`.
3. otherwise → `resolve_alias(ref, organization_id, team_id)` → **the latest valid version**.

Resolution is org/team-scoped via the ambient `ArtifactRunScope` (`:59-81`). A registry outage
degrades to `None` with a warning (`:851-853`), never a raise.

**Where resolution happens for a graph run is the important part.** For a `$initial_artifacts`
binding, the alias→uuid resolution happens **before any node runs**, and the resolved id is
recorded in run metadata as `{"ref": …, "resolved_id": …}` per name — the lockfile rule
(`docs/dashiboard.md:150-158`). The node's input then receives the **resolved uuid string**,
never the alias and never a loaded object. So a run is reproducible: months later you can see
exactly which version it consumed.

### 3.3 How `ConfigInput` merges

`ConfigInput` (`agentgraph:src/agentgraph/tools/platform/spec.py:76-89`) declares a parameter
that is an artifact *reference to a config*, plus the tuple of payload fields it may supply. For
dashi (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:150-161`):

```python
ConfigInput(param="pipeline_artifact", fields=("nodes", "groups", "filters"), description=…)
```

Two mechanisms:

**Signature demotion**, at tool-generation time (`spec.py:248-274`). A field that is *required*
by the payload schema but *could* come from a config is **demoted to optional** in the generated
signature, with its description suffixed `"(required unless supplied via pipeline_artifact)"`.
For dashi that is `nodes` (`remote_procedure.py:246-253`, `min_length=1`).

**The merge**, at call time (`spec.py:277-317`):

1. skip if the param is `None`;
2. `ARTIFACT_STORE.resolve_entry(ref)` — §3.2's resolution — raising if it does not resolve to a
   *materialized* artifact (`:296-300`);
3. `ARTIFACT_STORE.get(entry.id)` and require a `dict` (`:302-306`);
4. **reject unknown keys**: `set(cfg) - set(ci.fields)` raises, naming what it may supply
   (`:307-312`). A config with a stray top-level key is a hard error, not a warning;
5. `resolved[ci.param] = entry` — the entry is kept for provenance and preflight;
6. `for f in ci.fields: if merged.get(f) is None and f in cfg: merged[f] = cfg[f]`.

**The merge rule, stated exactly** (`spec.py:86-88`, `:283-286`): **`None` means omitted.** Any
non-`None` explicit value wins — **including `[]` and `{}`**. An explicit empty `filters` list
deliberately overrides the config's filters. Then `_enforce_required_after_merge`
(`:320-329`) checks the demoted names are non-`None` and raises naming both the missing fields
and the suppliers.

**The config param never reaches the wire** (`spec.py:80-83`) — it is loaded client-side and
its fields are spliced into the payload. **The config artifact joins the output's
`data_lineage` whenever it was *provided*, even if fully overridden** (`spec.py:456-460`) —
provided means provenance. So a result table records both its data parent and its config
parent.

### 3.4 What `content_metadata["required_columns"]` is, and who writes it

**Who writes it: the generated `dashiboard_validate` tool, and nothing else.**
`agentgraph:src/agentgraph/tools/platform/spec.py:625-639`:

```python
sv, ov = res.get("source_vars"), res.get("output_vars")
if sv is not None and ov is not None:
    for ci in spec.config_inputs:
        entry = resolved.get(ci.param)
        if entry is not None:
            ARTIFACT_STORE.annotate(entry.id, {
                "required_columns": sorted(set(sv) - set(ov)),
                "produced_columns": list(ov),
            })
```

**When:** after the server's `validate` returns a verdict carrying `source_vars`/`output_vars`.
Old servers returning a bare `{"valid": true}` annotate nothing (`:625-628`).

**Why the subtraction:** the server's `source_vars` is a *syntactic union* of column selectors
and may name a column another card produces; subtracting `output_vars` leaves the **root**
columns the pipeline reads (comment at `spec.py:622-625`, doc at `docs/dashiboard.md:231-235`).

**How it is stored:** `ARTIFACT_STORE.annotate` (`artifact_store.py:754-773`) merges the patch
into `content_metadata` **registry-side** via `patch_metadata` (JSONB `||`), so concurrent
annotators never clobber each other's keys. It is **advisory by contract — it never raises**
(`:756-759`); a failure degrades to a warning. Safe on immutable rows because a fact derived
from bytes that never change cannot go stale.

**What consumes it — as a code path, not as observed behaviour.** Everything in this subsection
describes wiring that exists and has **never fired in production**: only `dashiboard_validate`
writes `required_columns`, and that tool calls a method ET does not serve (§0.5.1). Read it as
the contract to satisfy, not a check in place. `_dashi_preflight`
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:72-82`) reads it off the
`pipeline_artifact` and diffs it against the *source* artifact's recorded `columns`, before any
HTTP:

```python
required = (getattr(pentry, "content_metadata", None) or {}).get("required_columns")
if required:
    missing = sorted(set(required) - names)
    if missing:
        findings.append(f"the pipeline artifact requires columns {missing} that are "
                        f"not in the source table (columns: {sorted(names)})")
```

Absent metadata checks nothing (`:37-39`) — old rows stay usable and the server remains the
runtime authority. The `columns` on the source side come from the parquet **footer** at
registration, via `_make_table_file_describer`
(`agentgraph:src/agentgraph/tools/artifact_codecs.py:383-407`) — schema plus row count, no data
load.

**⚠ Contradicts the spec — a scoping caveat on decision §2.** §2 says the config carries no
`DataFlow` and is source-agnostic, and separately that the UI annotates `required_columns`. Both
are right individually, but note they are in slight tension: `required_columns` **is** a
statement about a source, just a weaker one (a set of names rather than a binding). It is a
sound compatibility *contract* — "any table with at least these columns" — and that is exactly
what preflight uses it for. I raise it only so nobody later reads it as a source binding. Also:
it is derived from a *validated* config, so a UI that saves a draft the server would reject
cannot annotate it, and the artifact will carry no `required_columns` at all. Preflight then
checks nothing, which is the correct fail-open, but the catalog's "Needs: …" line will be blank.
**Recommendation: make the annotation the outcome of an explicit "Validate" action rather than a
side effect of "Save", so a blank one is legible as "not yet validated" rather than "no
requirements".**

### 3.5 What a DashiBoard UI must call to save a config — and the gap

**The good news: it is one POST, and yes, it works from a browser.**

`POST /v1/artifacts` (`agentgraph:src/agentgraph/api/routes_artifacts.py:223-291`), multipart
form:

| field | value |
|---|---|
| `file` | the config as a file — `.json` or `.toml` |
| `alias` | e.g. `std-preprocess` (validated: single path segment, no `../` — `:68`, enforced at `:238` *before* any filesystem work) |
| `description` | free text, required |
| `artifact_type` | `structured_data` |
| `artifact_format` | `json` or `toml` (optional; inferred from suffix) |
| `parent_keys` | optional list of uuid / alias / `alias@version` |

Returns **`{"id": <uuid7>, "alias": <alias>, "version": "1.0.N"}`** (`:288-291`). Streamed to
disk with a size cap (`:255-266`), registered through `register_file`, `origin="upload"`.
A second POST under the same alias creates version `1.0.N+1` — **that is how the UI saves a
revision.**

Both formats are real codecs: `("structured_data","json")` and `("structured_data","toml")`
(`agentgraph:src/agentgraph/tools/artifact_codecs.py:490-510`), each with a `describe_file`, so
registration records shape facts either way. TOML matters because your pipeline documents are
TOML today (`agentgraph:configs/dashiboard/pipeline.toml`).

Read-back for the UI: `GET /v1/artifacts` (list, filterable by `artifact_type`, `:205-221`),
`GET /v1/artifacts/{ref}` (detail with version history, `:447-478`), `GET
/v1/artifacts/{ref}/content` (`:329+`), `DELETE /v1/artifacts/{ref}` (`:480+`). `ref` accepts
uuid or alias throughout.

**Auth: there is none.** No API key middleware, no `Depends`, no `HTTPBearer`, no `Security(`
anywhere in `src/agentgraph/api/`. nexus-weaver-pro sends `VITE_METAGRAPH_API_KEY` and the
server ignores it. The only access control is **CORS**, a hard-coded three-origin allowlist
(`agentgraph:src/agentgraph/api/main.py:55-64`):

```python
allow_origins=["http://localhost:8080", "http://127.0.0.1:8080", "http://192.168.4.42:8080"],
allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
```

**Convenient accident: ExperimentTracking defaults to port 8080.** A DashiBoard UI served by
Julia at `localhost:8080` is *already* an allowed origin and can call these routes from the
browser today with no change on my side. Whether you should rely on that is a different
question — it is a hard-coded literal, not a policy, and it silently stops working the moment
anyone changes a port. **Recommendation: make the allowlist an env var before depending on it.**

**⚠ The gap — this is what must be built.** The upload route has **no `content_metadata`
parameter**, and `_build_index_element` sets `content_metadata` from the describe facts *only*
(`artifact_store.py:283-285`, `:310`). There is **no PATCH/annotate route** on
`/v1/artifacts` — the outline is GET status, GET list, POST "", POST /register-path, GET
`{ref}/content`, GET `{ref}`, DELETE `{ref}`. So **a browser cannot write `required_columns`
today**, and decision §2's "the UI annotates what it saves" is not implementable against the
current API.

Two ways to close it, both small, both in my repository, both listed here as recommendations I
am ready to implement on `ds-DashiUI`:

- **(A) `PATCH /v1/artifacts/{ref}/metadata`**, body `{"content_metadata": {...}}`, calling
  `ARTIFACT_STORE.annotate(ref, patch)`. ~15 lines. Cleanest: it matches the existing
  annotate-after-validate lifecycle, works on an already-saved artifact, and reuses the JSONB
  merge so a UI annotation and a later `dashiboard_validate` annotation compose instead of
  clobbering.
- **(B) an optional `content_metadata` form field on `POST /v1/artifacts`**, threaded into
  `register_file` → `_build_index_element`. Saves a round trip, but `register_file` has no such
  parameter today and adding one touches the shared constructor both write paths use.

**I recommend (A).** It is additive, it does not touch the store's constructor, and it keeps
"describe facts are derived, annotations are asserted" as two distinct provenance classes —
which is worth preserving, because today you can trust that anything in `content_metadata` on a
fresh row was computed from the bytes.

### 3.6 The full lifecycle, end to end

```
UI authors {nodes, groups, filters}
   │
   ├─(1)─ POST /v1/artifacts  (multipart: file=config.toml, alias, description,
   │                           artifact_type=structured_data)          → {id, alias, version}
   │
   ├─(2)─ validate: today, an AgentGraph tool call (dashiboard_validate) against a real
   │        source artifact; the server returns source_vars/output_vars and the tool
   │        annotates required_columns + produced_columns onto the config artifact
   │        [UI-driven equivalent needs §3.5(A)]
   │
   ├─(3)─ a graph run binds it:  initial_artifacts={"pipeline_in": "std-preprocess"}
   │        → alias resolved to a uuid BEFORE any node runs; {ref, resolved_id} recorded
   │
   ├─(4)─ the function node's input receives the resolved uuid; the tool loads the dict and
   │        merges its fields into the payload (None = omitted, explicit wins)
   │
   ├─(5)─ preflight: id_var / filters[].colname / groups[].cols / required_columns vs the
   │        source artifact's recorded columns — milliseconds, before any HTTP
   │        [only the first three actually run today; the required_columns arm has never
   │         fired, and simple {cols=[...]} is the only group shape covered — §0.5.4]
   │
   ├─(6)─ JSONRPC POST {url}api/v1  {id, method, params}   → ExperimentTracking → Pipelines
   │
   └─(7)─ the written parquet is registered as a new artifact, data_lineage = [source, config]
```

---

## 4. The services layer as an embedding mechanism

**Confirmed, with correction 0.2 applied.** `routes_services.py` carries the URL, not the
traffic. `_project` (`:68-104`) is an explicit **whitelist**, not a serializer — the module
docstring (`:5-9`) is emphatic about why: a spec holds live callables (`connection_factory`,
`preflight`, `result_adapter`, `output_metadata`) that must never reach a JSON response, so
every emitted field is named rather than `vars(spec)`-dumped. The one route that dials the
service is `/health` (`:160-178`), which runs `discover()` off the event loop and catches
broadly so unreachability is a field, never a 500.

**What `GET /v1/services` actually gives an embedder.** More than a URL — it returns
`operations` as `{op: model.model_json_schema()}` (`:81-83`), i.e. the full JSON Schema of the
dashi train/eval payloads, plus `artifact_inputs`, `config_inputs` (with their `fields` tuple),
`artifact_outputs`, `output_keys`, `validate_operation`, and the resolved `connection` block
with **per-field provenance** (`"configured"` | `"env"` | `"default"`, `:74`). For nexus that is
a genuinely useful discovery document: the URL to iframe, and a machine-readable statement of
what the service accepts.

`PUT /v1/services/{service}/connection` (`:113-139`) is the editable half, and its
"absent vs present-and-null" handling via `model_fields_set` (`:125-128`) is worth copying if
you ever build a partial-update endpoint — it is the only correct way when `None` is itself a
meaningful value.

### Should nexus talk to ExperimentTracking directly, or proxy through me?

**Direct. Do not proxy through AgentGraph.** There is no proxy today (no forwarding route
exists in `src/agentgraph/api/`) and I would not add one. The costs, concretely:

| | direct (browser → Julia) | proxied (browser → AgentGraph → Julia) |
|---|---|---|
| **latency** | one hop | two, plus JSON re-encode of every payload |
| **streaming** | ET's own progress events reach the browser | I would have to bridge them into Redis pub/sub and re-emit — a second `StreamEvent` shape for events I do not model |
| **payload coupling** | none | every ET API change becomes an AgentGraph release; `DashiTrain`/`DashiEval` (`remote_procedure.py:233-279`) already have to track ET's payloads, and today that coupling is worth it because it buys probe-time validation. A pass-through proxy would take the coupling and buy nothing. |
| **process** | — | the API process would start doing long-running I/O it currently delegates to the worker. The API is `--reload`-hosted in dev and already goes unavailable for ~8 s on any code edit; adding a 120 s-timeout upstream to it is the wrong shape. |
| **auth** | ET's own (whatever you build) | mine — and I have none (§3.5). A proxy would be an unauthenticated open relay to a service that writes files. |
| **what I'd gain** | — | one origin. That is all. |

**And the one origin is not worth it**, because decision §10 already gets it for free: ET serves
the UI's assets, so an iframe whose `src` is the resolved RemoteService URL is same-origin
*inside the frame*. AgentGraph's job in that story is to be the **directory** — the thing that
knows the URL and can prove it is reachable — which is exactly what `GET /v1/services` and
`GET /v1/services/dashi/health` already are.

**What I would want in exchange, if nexus embeds via `RemoteService`:** the projection currently
exposes `connection.url` and I am content for that to be the embed source. But note the URL is
the **JSONRPC base** (`http://127.0.0.1:8080/`, with `api/v1` joined onto it at call time —
`remote_procedure.py:364`). If the UI lives at a different path on the same host, either the
embedder appends the path by convention, or the spec grows a `ui_path` field. The latter is a
three-line change on my side (`RemoteServiceSpec` at `spec.py:91-125` plus one line in
`_project`) and I would rather do that than have nexus hard-code a path suffix. **Ask me for it
when you know the path.**

**One caution about `/health` as an embed precondition.** `discover()` calls the `cards` method
(`remote_procedure.py:438-440`) with `timeout=min(connection.timeout, 10.0)`. It is a real
round trip, not a HEAD. If nexus polls it to decide whether to show the DashiBoard menu item,
poll it slowly — it makes ET do card-schema work each time.

---

## 5. The wire, as built

### 5.1 The envelope

Three request builders, all in `agentgraph:src/agentgraph/tools/remote_procedure.py`, all
emitting the same shape:

```python
{"id": next(_rpc_ids), "method": <method>, "params": <params>}
```

`call` `:359-363`, `validate_remote` `:408-412`, `discover` `:438-440`. `_rpc_ids` is a
process-local `itertools.count(1)` (`:46`) — so `id` is an **int**, unique within a process,
**not** across the worker's restarts or across processes. Nothing correlates on it.

The documented dialect notes (`:18-24`), verified against the live implementation per their own
comment:

- one route, `POST {url}api/v1` — built with `urljoin(self.connection.url, "api/v1")` (`:364`),
  which is why the default URL carries a **trailing slash** (`:75`); without it `urljoin` would
  eat the last path segment;
- the envelope's version field is `version`, not `jsonrpc` — **but nothing sends it** (see §0.1);
- `id` must be an int;
- **HTTP status is 200 even for failures — parse the body, never the status.** Enforced by the
  comment at `:372` and by there being no `raise_for_status()` anywhere;
- errors arrive as `{"error": {"code", "message"}}` with **no `result` key** — hence the guard
  `if "error" in data and "result" not in data` (`:373`, `:422`, `:443`).

### 5.2 Methods called

| tool | `operation` | wire `method` | where |
|---|---|---|---|
| `dashiboard_train` | `train` | `train` | `_method_name` `:381-385` |
| `dashiboard_eval` | `eval` | **`evaluate`** | the one mapping, `:383-384` |
| `dashiboard_validate` | `eval` (superset surface) | `validate` — **NOT SERVED, see §0.5.1** | `:410`; `validate_operation="eval"` at `dashiboard.py:149` |
| `/v1/services/dashi/health` | — | `cards` | `discover` `:439` |

### 5.3 Connection resolution

Three layers, merged **field by field**, **read fresh on every call, no cache and no TTL**
(`resolve_connection`, `:157-170`):

```
Postgres service_connections row  →  env  →  built-in default
```

- env layer: `DashiConnection.from_env()` (`:71-77`) — `DASHIBOARD_URL` default
  `"http://127.0.0.1:8080/"`, `DASHIBOARD_TIMEOUT` default `120` seconds.
- the DB row overrides **only the fields it sets**, non-destructively, onto a `model_copy()`
  (`:163-169`). A row setting only `url` still takes `timeout` from env.
- `resolve_connection_detailed` (`:173-193`) computes the same merge plus per-field provenance.
  Provenance for `"env"` is decided by **`os.getenv(name) is not None`** — whether the var is
  *set* — never by inspecting a value `from_env()` already defaulted (`:80-85`, `:189`).
- **A broken connection store degrades to env with one warning, never raises**
  (`_fetch_connection_row`, `:135-154`, deliberately broad `except`). A config-store outage
  reverts tool calls to pre-feature behaviour instead of stopping them.

The no-cache decision is load-bearing: the worker, the API and the health probe cannot disagree
about where the service is.

### 5.4 Payload assembly

Both `DashiTrain` (`:233-268`) and `DashiEval` (`:271-279`, adding `from_run` aliased to `from`)
are `extra="forbid", populate_by_name=True`. `DataFlow` (`:196-230`) is a nested model — but
**the wire is flat**:

```python
body = validated.model_dump(by_alias=True, exclude_none=True)
flow = body.pop("dataflow", {})
params = {**flow, **body}
```

(`:355-358`.) The DataFlow fields sit side by side with the pipeline fields in `params`. The
nesting exists only so the spec can address wire fields by dotted path
(`"dataflow.source"`, `dashiboard.py:94`).

`DataFlow`'s field descriptions are explicitly *"builder-facing contract prose"* copied verbatim
into the generated tool docstrings and args schemas (`:200-203`) — **the one place that contract
is written down**. That is a pattern I would repeat: put the prose on the model, generate every
audience's copy from it.

**⚠ `load_options` is a dead field.** `DashiTrain.load_options` (`:259-263`) was renamed
`source_options` and moved inside `DataFlow` on the ET side; the key I send is ignored and the
caller's reader options vanish silently. See §0.5.2.

`fixed_fields={"dataflow.file_based": True}` and
`excluded_fields={"dataflow.schema_", "dataflow.database"}` (`dashiboard.py:118-121`) mean
db-mode qualifiers can never appear on the wire. **AgentGraph talks to DashiBoard in file mode
only.**

### 5.5 Validation, at four points

1. **Client-side schema**, `validate_operation` (`:290-312`) — raises `RemoteProcedureError`
   with pydantic's field-level detail. Wire-shape errors stay ours.
2. **Probe mode** — `call` short-circuits *after* validation and *before* any HTTP
   (`:345-350`), returning `{"probe": True, service, operation}`. This is what makes a graph
   containing a dashi tool checkable at save time without running a pipeline.
3. **Preflight** — `_dashi_preflight` (`dashiboard.py:29-83`), see §5.6.
4. **Server-side** — `validate_remote` (`:387-428`) asks ET for a `validate` **method**.
   **⚠ That method does not exist on ET `main`** — validation-without-execution is the route
   `POST api/v1/probe`. This rung is currently broken and misreports itself as a content
   verdict; see §0.5.1.

The verdict contract is the part I am proudest of. A **rejection** returns
`{"valid": False, "errors": "<the server's own message>"}` (`spec.py:618`) — a *finding*, never
an exception, so an iterating agent can act on it. An **unreachable service** raises
`RemoteUnreachableError` and is deliberately re-raised past the handler (`spec.py:615-616`):
*"no verdict was given — never report it as one"*. Because the server's validation runs exactly
the request-validation phase of a real call, **"validate accepts" and "train would accept" are
the same statement by construction** (`docs/dashiboard.md:196-199`) — **an aspiration today, not
a fact: the method being called is not served, so nothing is validated. See §0.5.1, which also
explains why the probe route makes this claim truer than I originally argued.**

`_parse_rpc_body` (`:323-338`) deserves a mention: a non-JSON body means whatever answered is
**not the service**, and it raises `RemoteUnreachableError` naming the URL rather than leaking a
`JSONDecodeError`. That was written after a real incident — a default URL reached the web UI's
dev server, which returned HTML, and the parse error read as a payload problem.

### 5.6 Preflight column checks — and their real limits

*(Read this subsection with §0.5.4 in hand: of the four checks below, the `required_columns` arm
has never fired, so only the first three describe running behaviour. And with §0.5.6: two of
these checks — `id_var` and `filters[].colname` — are the ONLY coverage of their paths and must
survive any server-side improvement, including my own #12.)*

`_dashi_preflight(kw, resolved)` (`dashiboard.py:29-83`) runs **after artifact resolution,
before payload assembly and before any HTTP**, against the source artifact's recorded
`content_metadata["columns"]`. It checks `id_var` (`:63`), `filters[i].colname` (`:64-66`),
`groups[gname].cols` (`:67-70`), and `required_columns ⊆ columns` (`:72-82`).

Two nice touches: `kw` arrives **merged**, so config-artifact-supplied filters and groups are
checked exactly like explicit ones (`:32-34`); and a **blank** value is reported as "is empty —
set it to one of…" rather than "references column ''" (`:48-57`), because the UI's schema
template seeds string params as `""` and the wrong message sent people hunting a pipeline bug.

**But the group handling only covers the simplest group shape, and this matters for decision
§6.** The loop is:

```python
for gname, group in (kw.get("groups") or {}).items():
    if isinstance(group, dict):
        for col in group.get("cols") or []:
            check(col, f"groups[{gname!r}].cols")
```

Per `00-dashiboard-context.md`, a group is written in the full variable vocabulary: an item may
carry `nodes` or `groups` instead of `cols`, may be qualified by `through`, and **may be a list**
(a union). Against that model this loop:

- **silently skips a list-valued group** — `isinstance(group, dict)` is `False`;
- **silently skips `{nodes=[…]}` or `{groups=[…]}`** — `group.get("cols")` is `None`.

Neither is *wrong* (it fails open, and absent-metadata-checks-nothing is the stated contract at
`:37-39`), but a user authoring the richer groups decision §6 requires gets **no local column
checking at all** and only finds out at the server. `required_columns` partially covers this
*if* the config was validated — which is the loop closing back on §3.5's gap.

**Recommendation — REVISED 2026-09-01, and reversed in direction.** My original text here was
"generalize the preflight to walk one-or-list dependency items". **That is the wrong direction
and it is withdrawn.**

Extending the preflight to track DashiBoard's dependency grammar would mean holding a second,
partial copy of that grammar inside AgentGraph — and **every increment of another system's
grammar held locally is a rot surface.** `load_options` (§0.5.2) is the proof: one renamed field
on the Julia side, silently ignored here, producing a mis-parsed table with no error anywhere.
Generalizing the preflight would have created four more fields of exactly that kind, and the
richer the UI's group vocabulary gets (decision §6), the faster the copy drifts.

The correct shape is **#12, not #3**: send ET the column list via `source_metadata["cols"]` and
let **ET** check the references against its own grammar, which it already does
(`initialize_pipeline`, `ET:src/entries.jl:130-134`). One fact crosses the wire; the authority
stays with the system that owns the vocabulary.

So the revised recommendation is: **FREEZE `_dashi_preflight` at its current narrow arms and do
not extend it.** Keep `id_var` and `filters[i].colname` — they are the only coverage of those
paths and must survive (§0.5.6) — keep the simple `groups[].cols` arm that already exists, and
let #12 carry everything else. The preflight's remit is "column names against a table whose
metadata I hold, fail-open on anything unrecognized", never "understand the pipeline document".

### 5.7 The parquet exchange

`write_table` (`agentgraph:src/agentgraph/tools/artifact_codecs.py:107-147`):

```python
con.register("_src", data)
con.execute(f"COPY _src TO '{p}' ({fmt_opts}{extra});")
```

with `fmt_opts` one of `FORMAT PARQUET` / `FORMAT CSV, HEADER` / `FORMAT JSON` (`:139-143`).
The docstring says it plainly (`:118-122`): *"This is the same `COPY ... TO` mechanism
ExperimentTracking.jl uses on the Julia side — both ends of the DashiBoard integration write
parquet through duckdb, which is the point of file-as-interface."*

Reading is symmetric: `_make_table_reader` (`:157-169`) does
`SELECT * FROM read_parquet('<p>')` through the same engine. Describing is cheaper still —
for parquet, duckdb reads schema and row count **from the footer**, no data load (`:384-386`).

Two hardening details worth stealing: duckdb interpolates paths into SQL with **no
bind-parameter option**, so both sides **refuse** a path containing a single quote rather than
escaping it (`:129-132`, and `_no_quotes` at `:61`); and `write` returns *how-to-load hints*
(`reader_options`, `primary_key`) that land in `storage_metadata`, kept strictly separate from
the *shape facts* (`columns`, `row_count`) that land in `content_metadata` (`:417-424`). That
separation is what lets `content_metadata` be trusted as derived-from-bytes.

Data **never round-trips through the Python process**: the artifact's parquet path is handed to
DashiBoard directly and the server reads and writes the files itself
(`dashiboard.py:96-100`).

### 5.8 What I wish that API gave me and does not

Ranked by how much it would change my code.

1. **Structured errors.** Today a rejection is one prose blob that I pass through verbatim
   (`spec.py:618`). It is *good* prose — the card index and JSON-Schema path are in it — but I
   cannot key on it, count it, group it, or attach it to a field. `{"errors": [{"path":
   "nodes/1/card/method", "culprit": …, "issue": …}]}` would let me surface findings per node
   instead of per call. **This is the single highest-value change to the ET API for a UI
   refactor**, because it is the same contract the browser form needs (decision §3), and you are
   already producing `SchemaValidationError(culprit, issue)` internally.

2. **`validate` without a source.** ~~As written below~~ — **largely already granted, and my
   framing was wrong: see §0.5.3.** `source_metadata["cols"]` already lets ET check a pipeline
   against a declared column list. What remains is whether `source`/`destination` can be relaxed
   for a fully source-free probe. Original text follows, for the record.
   `dashiboard_validate` currently requires a real
   `source_artifact` (`spec.py:589-598` raises if it does not resolve to a materialized table).
   A UI drafting a pipeline before a source is connected cannot validate at all — and decision
   §2 explicitly makes the saved document source-agnostic. A `validate` mode that checks card
   schemas and dependency structure with no `dataflow` would let the UI validate continuously
   while authoring, and would let me annotate `required_columns` at save time rather than at
   first-use time.

3. **A schema method that speaks the group vocabulary.** This is your §12 "schema dialect gap"
   seen from the outside. `discover()` gets `cards` (labels only). To offer a designer real card
   schemas with live column names I would want `schema` — and per your §12 it currently reaches
   the flat `schema_definitions(::AbstractVector)` rather than the `VariableConfig` method, so
   it cannot express `{nodes|groups|cols, through}`. **Whatever you build for the UI, I want the
   same endpoint**, and I would wire `discover()` to it or add a second probe. That is the one
   place where your refactor directly upgrades AgentGraph.

4. **A stable idempotency key on `train`.** `run_id` is caller-chosen and recorded, but a retried
   call after a timeout creates a second run. With a 120 s default timeout and pipelines that can
   exceed it, this is a real duplicate-work path.

5. **Column *types* in the validate verdict.** I get `source_vars`/`output_vars` as names. With
   dtypes I could preflight type mismatches, not just presence — I already have dtypes on the
   source side from the parquet footer.

---

## 6. Graph declaration, and where the two models agree

### 6.1 The node record

`NodeConfig` (`agentgraph:src/agentgraph/core/types.py:174-227`): `id`, `type`, `name`,
`timeout`, `parameters`, `defer`, `inputs`, `outputs`, `template_variables`, `prompt_template`,
`tools`, `aliases`, `headroom`, `mcp`, `skills`. Two validators: `type` must be a registered
`NODE_SPECS` key (`:211-218`) and `parameters` is validated against that type's model
(`:220-227`). The comment at `:178-180` records why the first exists — an unconstrained `str`
is why the loader once accepted `agent_node` and the weakest gate answered `valid=true` for
documents the write gate rejects.

`GraphConfigBaseModel` (`:294-306`): `id`, `version` (default `"2.2.0"`), `name`, `description`,
`nodes` (**`min_length=1`** — an empty config can never be valid, `:301-302`), `edges`,
`retry_config`, `metadata`, `conversation`.

### 6.2 How a node declares what it consumes

`InputConfig` (`:10-35`). The `from` field carries the whole model, as one regex:

```python
from_: Optional[str] = Field(None, alias="from", pattern=
  r"^\$initial_inputs(\.[^.\s]+)?$|^\$initial_artifacts(\.[^.\s]+)?$|^[^.\s]+\.[^.\s]+$")
```

Four source kinds, discriminated by prefix and dot count:

| form | meaning |
|---|---|
| `node_id.output_name` | **exactly one dot**, one source per input — a node edge |
| `$initial_inputs` | the whole initial-inputs dict, bound by this input's own name |
| `$initial_inputs.<field>` | one initial field, renamed to this input's name |
| `$initial_artifacts` / `$initial_artifacts.<name>` | a run artifact binding; the engine substitutes the **resolved uuid** |
| *(omitted)* | fall back to name-matching against the graph's output index |

`is_run_source()` (`:80-84`) is the predicate that keeps run sources out of edge inference.
**One source per input, always** — an input fed by alternative branches must be declared as
separate optional inputs (`:26-28`).

### 6.3 Edge inference — four phases

`ConfigLoader.load_config` (`agentgraph:src/agentgraph/core/loader/config_loader.py:20-61`):

```python
output_index      = build_output_index(config)
data_flow_result  = infer_data_flow_edges(config, output_index)
auto_inherit_edges, new_nodes = infer_auto_inherit_edges(config)
loop_feedback_edges = infer_loop_feedback_edges(config)
config.edges = merge_edges(config.edges, data_flow_result.edges,
                           auto_inherit_edges, loop_feedback_edges)
apply_tool_loop(config)
validate_routing(config)
```

**Phase 1 — data flow, by NAME** (`inference/data_flow.py:9-90`). For every input with **no**
`from:`, look up `output_index[input.name]`. Skip run sources (`:20-27`) and loop inputs
(`:29-35`). Skip inputs that *do* have a `from:` (`:41-48`) — the comment records the bug that
taught them: name-matching an explicit `from:` fed a **second** producer into the same input
slot whenever the name happened to collide. Zero matches → warn and continue. **More than one
match → record an ambiguity and wire nothing** (`:59-67`). Router outputs are skipped (`:71-78`).

**Phase 2 — explicit `from:`** (`inference/auto_inherit.py:96-133`). Split on `.`, require
**exactly two parts** or raise naming the node, the input and the expected forms (`:107-114`).
Then `update_node_aliases` **verifies the producer actually declares that output** and raises
naming the consumer, the reference, and the producer's real outputs (`:79-89`). It also records
the rename in the producer's `aliases` map, which is how a renamed output reaches a consumer.

**Phase 3 — loop feedback** (`inference/loop_feedback.py`), from `OutputConfig.feeds_back_to`.

**Phase 4 — tool loop** (`inference/tool_loop.py`), auto-creating `<agent>__tools` sibling nodes
and their iteration edges.

**Explicit edges are terminal only.** In the designer schema the `edges` array is constrained to
`{"source_node_id": {"pattern": "^[^$]"}, "target_node_id": {"const": "__end__"}}`
(`derive.py:303-326`), with a long `description` stating the convention. `$initial_inputs` and
`$initial_artifacts` are **run-supplied sources, not edges and not node ids**.

### 6.4 A real config

`agentgraph:configs/graph_configs/array_summary_statistics.yaml` (abridged; prompt elided):

```yaml
id: array_summary_statistics
name: "Array Summary Statistics Calculator"
version: 2.4.4
nodes:
  - id: statistics_calculator
    type: agent
    parameters:
      model_provider: bedrock_converse
      model_name: eu.amazon.nova-2-lite-v1:0
      model_extra_params:
        region_name: eu-central-1
        credentials_profile_name: ottante
      temperature: 0.1
    timeout: 300
    max_tool_iterations: 2          # <-- SILENTLY IGNORED: belongs under `parameters`
    template_variables: [numbers, tool_result]
    inputs:
      - name: numbers
        type: list
        from: $initial_inputs
    outputs:
      - name: statistics             # <-- ALSO names the auto-injected finish tool
        type: dict
    tools:
      - name: compute_array_statistics
        registry_key: compute_array_statistics
        description: Compute comprehensive summary statistics for an array of numerical values
edges:
  - source_node_id: statistics_calculator
    target_node_id: __end__
```

Two of this brief's findings are visible in eight lines of a shipped config: the ignored
node-level key (§1.6), and the output whose *position* names the finish tool (§2d) — the prompt
at line 43 says *"call the `statistics` tool"* because `statistics` is `outputs[0]`.

And the canonical dashi wiring, from `agentgraph:docs/dashiboard.md:80-133`:

```yaml
  - id: fit
    type: function
    parameters: {registry_key: dashiboard_train}
    inputs:
      - {name: source_artifact,    type: string, from: $initial_artifacts.train_source}
      - {name: destination_alias,  type: string, from: $initial_inputs.train_destination}
      - {name: id_var,             type: string, from: $initial_inputs}
      - {name: nodes,              type: list,   from: $initial_inputs}
      - {name: groups,             type: dict,   from: $initial_inputs}
    outputs:
      - {name: trained_run_id,   type: number}
      - {name: output_artifact_id, type: string}
  - id: apply
    type: function
    parameters: {registry_key: dashiboard_eval}
    inputs:
      - {name: from_run, type: number, from: fit.trained_run_id}
      # ...
edges:
  - {source_node_id: apply, target_node_id: __end__}
```

`from: fit.trained_run_id` is the whole edge declaration. **The wiring IS the artifact
contract**: `from: $initial_artifacts.train_source` names, in the config, exactly what a run must
bind — and `GET /v1/graphs/{id}` projects it as `artifact_inputs`
(`agentgraph:src/agentgraph/api/routes_graphs.py:96-99`) so a UI can build the run form from the
graph document alone.

### 6.5 Where the two models agree and differ

**Agree — and this is genuine convergence, not coincidence:**

- **Edges are inferred from consumption, never declared.** Both. Neither has an edge object in
  the authored document (ours has an `edges` list, restricted to terminal `→ __end__`); neither
  supports user-drawn connections. Both derive the DAG from what each node *names*.
- **A node names variables, not nodes.** Ours: `from: node_id.output_name`. Yours: `{nodes =
  ["log"]}`. Both address the producer through its data, not through a topology.
- **Automatic layout follows.** Decision §5's "no node positions are stored anywhere — the
  layout is a pure function of the document" is already true of ours by omission: nothing in
  `NodeConfig` is presentational. **I endorse this strongly and would resist any pressure to add
  positions.** The moment a position is stored, the document stops being a pure description and
  every non-UI writer (our builder LLM; your import path) has to invent one.
- **Both auto-create machinery nodes.** Our `apply_tool_loop` creates `<agent>__tools` siblings
  that the author never writes and cannot usefully declare — hence `designer_facing=False`. If
  DashiBoard grows anything similar, copy the flag: a type that is real at runtime and invisible
  at authoring time needs to be *marked*, not just undocumented.

**Differ:**

| | AgentGraph | DashiBoard |
|---|---|---|
| **reference granularity** | `node_id.output_name` — one **named output** of one node | `{nodes = ["log"]}` — **every** output column of those nodes (`deps.jl:107`) |
| **cardinality** | strictly **one source per input**; alternatives must be separate optional inputs (`types.py:26-28`) | one item **or a list**, and a list is a **union** (`Context` appends) |
| **selector kinds** | one, implicit (a node output) | **three**, explicit: `cols` \| `nodes` \| `groups`, exactly one per item |
| **qualifier** | none | **`through`** — a *renaming* (`pass_through` appends suffixes), not a filter |
| **named reusable sets** | none | **groups**, written in the same vocabulary, referencing nodes and other groups |
| **graph rendering** | node→node | **bipartite** — vertices for cards *and* variables |
| **discriminated union depth** | one level (node type) | genuinely nested (card → method → sub-method) |

**On `groups` and `through`, specifically — the thing you asked about.** We have **no analogue of
either**, and I want to be precise about why rather than implying we solved it differently.

Our `aliases` map (`types.py:191-192`) looks superficially like a rename mechanism, but it is
not: it is *derived* by `update_node_aliases` (`auto_inherit.py:32-93`) as a side effect of
inference, recording "this producer's output `x` is also known downstream as `y`". It is
bookkeeping the loader writes, not vocabulary an author uses. There is no way for an author to
say "these three outputs, as a set, under this name" — the closest thing is declaring the same
`from:` three times.

That absence is exactly why our `SchemaContext` never needed document-derived enums (§1.3): with
one selector kind and one source per input, the reference is a *string with a dot in it*, and a
regex is a defensible schema for it. **Your model is richer, and the richness is what forces
the harder schema.** `{selector-kind, value, through?}` as a repeatable item is a genuine
discriminated union at the *field* level, inside a card, inside a document — three of your four
levels — and its options are document-derived, not deployment-derived. It cannot be a regex.

So my honest read of decision §6: the "one picker, two levels" component is the right shape and I
would build it, but **it is the piece of this refactor with no precedent in my repository.** I
can tell you that our single-selector-kind model was cheap and that its poverty is what makes our
form unbuildable; I cannot tell you what the three-kind version costs. Treat §6 as the genuinely
novel work and do not let its resemblance to anything of mine imply it is derisked.

One thing I *can* offer from experience: **make the selector kind a real discriminator in the
schema** — `oneOf` with a `discriminator`, or a required `kind` field — rather than "an object
with exactly one of three optional keys". `deps.jl:41` already enforces exactly-one; encoding
that as three optional keys is what produces "is not valid under any of the given schemas"
(§1.6), and it is the difference between an error that names the field and one that names
nothing.

---

## 7. Validation, errors and streaming

### 7.1 How a config is validated

`evaluate_graph` (`agentgraph:src/agentgraph/core/dolt/registry.py:507-540+`) is **THE** validity
gate, and it **accumulates rather than raises**, so raise-vs-report is the caller's choice
(`:519-521`): `save_graph_version` raises on `not ok`, `POST /v1/hitl/verify` returns the
findings, publication re-verify demotes. **One implementation, one answer.** This is worth
copying wholesale — the single most common failure mode in a system with a UI and a CLI and an
agent is three validators that disagree.

The layers, from `verify_graph_yaml` (`:100-144`):

- **L1 — the derived schema** on the raw parsed document, `Draft202012Validator` (`:129-131`).
  **Fail-closed**: if the schema *context* cannot be built (catalog or Redis outage), a
  `status='valid'` write is **refused** rather than admitted unchecked; `draft` is the incident
  escape hatch (`:105-108`, `:120-127`).
- **L2 — full ConfigLoader inference** (`:137`), which raises structurally on a ghost `from:`,
  a bad route, a duplicate id.
- **L3 — cross-node semantics** (`_validate_semantics`, `:139-144`).
- then, in `evaluate_graph`: function-node **output** contracts (declared outputs ⊆ the tool's
  `output_keys`), function-node **input** names (`verify_function_node_inputs`, `:318-388`), and
  the **execution probe** (zero-I/O, tools return placeholders).

`tool_outputs_fail_open` (`:523-527`) routes tool-lookup failures to `warnings` at publication
time, so a transient Dolt hiccup at merge cannot demote a graph that already passed on its
branch — preserving "valid always publishes".

### 7.2 The exact error shape a UI receives — and why you should not copy it

```python
@dataclass
class ValidationReport:
    ok: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
```

(`registry.py:497-504`.) `POST /v1/hitl/verify` returns `{ok, errors}` (route
`agentgraph:src/agentgraph/api/routes_hitl.py:150-164`, service `api/services.py:545-580`).
`POST /v1/graphs` raises `HTTPException(422, detail=str(exc))` — **detail is a plain string**
(`routes_graphs.py:120-123`).

**`errors` is a list of prose strings. There is no path, no field, no code.** The closest thing
to structure is that L1 prefixes each schema error with a slash-joined JSON pointer before
flattening (`registry.py:129-131`):

```python
f"{'/'.join(str(p) for p in e.absolute_path)}: {e.message}"
```

...and then **joins the first ten with `"; "` into one string** (`:135`). So a UI receives, for
the config in §6.4 validated against the designer schema:

```
config failed derived-schema validation: nodes/0/parameters/model_name: 'eu.amazon.nova-2-lite-v1:0'
is not valid under any of the given schemas; nodes/0/parameters/model_extra_params/region_name:
'eu-central-1' is not valid under any of the given schemas
```

To attach that to a form field a UI must re-split on `"; "` and re-parse the pointer prefix out
of prose that also contains colons. **It cannot be done reliably, and our correction UI does not
try** — it renders the blob.

**⚠ This is where AgentGraph is worse than DashiBoard already is today, and decision §3 depends
on the thing we got wrong.** Your `SchemaValidationError(culprit, issue)`
(`Pipelines/src/group_api/schema.jl:71-99`) is *structurally better* than anything we ship:
two fields instead of one blob. Decision §3 makes the error contract load-bearing —
*"it is the only place some constraints become visible"* — so it has to be at least as good as
what you have, not as good as what I have.

Concretely, three things to fix that we did not:

1. **Errors are objects, not strings.** `{path, culprit, issue, severity}` at minimum. The path
   should be a JSON Pointer (or a segment array) so the form can address a field.
2. **Do not truncate.** Our `[:10]` cap (`:135`) means a config with eleven problems tells you
   about ten and lies about the rest by omission. Cap the *rendering*, never the payload.

2b. **Surface LEAF errors; never render a composition keyword.** Generalized from §0.5.7 and
   §0.5.8 — this is the cheapest error-quality win available to either of us, and it needs no
   schema change, so it lands before any schema fix.

   Discard `anyOf`/`oneOf`/`allOf`/`if` summaries, keep the deepest leaf per path, and pass the
   enum through as **structured data** rather than flattening it into prose. Measured on my own
   schema, the exact before/after:

   ```
   today      nodes/0/parameters/model_name: 'bogus' is not valid under any of the given schemas
   leaf-first nodes/0/parameters/model_name: 'bogus' is not one of
                                             ['us.anthropic.claude-sonnet-4-20250514-v1:0']
   ```

   The structured form is reachable in both stacks: Python `jsonschema` exposes
   `leaf.validator_value` (a real `list`, verified); Ajv exposes `params.allowedValues`. **A form
   can therefore render the options as selectable choices instead of reformatting a sentence** —
   which is the difference between an error that says "invalid" and one that offers the fix.

   **Which composition keywords actually leak is validator-specific — test yours, do not copy a
   list.** Measured (§0.5.8): on Python `jsonschema` only `anyOf` surfaces; `if`/`then` never
   does, so a bad value inside a variant already arrives as a bare leaf. Ajv additionally emits
   `if: must match "then" schema`. Same rule, different offenders.
3. ~~**Prefer `oneOf` + `discriminator` over `allOf` + `if/then` for the type union.**~~
   **WITHDRAWN — measured, and it was backwards. See §0.5.7.** My gated `allOf` + `if/then`
   produces exactly ONE correctly-pathed error in every case I tested. I asserted the opposite
   without ever running it, and misattributed the `anyOf` symptom (recommendation 1, which is
   real) to the union mechanism.

### 7.3 How "latest valid version" surfaces to a client

`load_graph_yaml` (`registry.py:793-838`) resolves by a **composite key**: graph id + branch
(from the *connection*, never `dolt_checkout`) + optional version pin + status rule. The default
is **latest-valid**, so *"a later failed registration can never shadow a working version"*
(`:802-803`). `require_valid=False` is the correction editor's status-agnostic read (newest row
of any status). Absent → `LookupError` naming `init_dolt` if the registry is empty (`:832-838`).

To a client the rule surfaces as **two version fields on the same row**
(`agentgraph:src/agentgraph/api/models.py:29-44`):

```python
class GraphMetadata(BaseModel):
    graph_id: str; name; description
    status: str = "valid"    # valid | failed | draft
    kind: str = "user"       # user | master
    version: Optional[str]        # the LATEST row, whatever its status
    branch: str = "main"
    updated_at; issue_id
    valid_version: Optional[str]  # the latest VALID row — what the runtime runs
```

`valid_version` is `None` iff the graph has never validated. So a client can distinguish
**"latest attempt failed but it is still runnable"** (`status="failed"`, `version="2.1.0"`,
`valid_version="2.0.0"`) from **"never validated"** (`valid_version=None`) — `:41-44`. That
distinction is the whole reason the field exists, and I would recommend the shape to any
registry with a status column.

`GET /v1/graphs/{graph_id}` (`routes_graphs.py:58-103`) returns both representations at once:
`parsed` (the authored document, **edges NOT complete**) and `resolved` (the post-inference
topology — *"This is what the UI renders"*, `:86-88`). A document that fails to resolve is
still returned, with `resolve_error` set and `resolved: null` (`:69-74`) — *"a failed candidate
is exactly what an operator opens the detail view to inspect"*. **That pattern is worth
copying**: never refuse to show a broken document; show it with its error attached.

### 7.4 The streaming contract

**Transport.** `WebSocket /v1/executions/{execution_id}/stream`
(`agentgraph:src/agentgraph/api/main.py:67-80`) — a thin bridge that subscribes to the Redis
channel `graph:exec:{execution_id}` and forwards each message's `data` verbatim as text. The
worker publishes with `publish_stream_event` (`api/services.py:348-350`),
`json.dumps(jsonable_encoder(event))`. **Pub/sub is ephemeral: a client connecting after an
event has missed it.** There is no replay.

**Event shape** (`agentgraph:src/agentgraph/graph/graph.py:28-33`):

```python
class StreamEvent(BaseModel):
    type: str
    node_id: Optional[str] = None
    data: dict[str, Any] = {}
    state: Optional[dict[str, Any]] = None
    timestamp: str
```

**Event sequence.** `astream` runs LangGraph with `stream_mode=["updates","values"]`,
`subgraphs=True` (`:1258-1262`) and demultiplexes the `(namespace, mode, payload)` tuples
(`:1266-1272`):

- `mode == "values"` → full state snapshot, **retained as `last_state`, not emitted**
  (`:1278-1280`);
- `mode == "updates"` → one `node_completed` **per node**, because a superstep may complete
  several parallel branches in one payload (`:1282-1284`). Payload:
  `data = {"raw": {node_id: update}, "headroom_metrics": {…}}`, `state=None` (`:1303-1311`).
  `__`-prefixed bookkeeping nodes are skipped (`:1285-1286`);
- finally one `type: "state"` event carrying the **real** final state (`:1341-1347`), with
  `execution_id`, `graph_id`, `status`, `start_time`, `end_time` filled in (`:1319-1331`);
- the worker appends `{"type": "done"}` on success or `{"type": "error", "data": {"error": …}}`
  on failure (`api/worker_tasks.py:67`, `:73`).

The comment at `:1254-1257` records the bug that shaped this: `stream_mode` was historically
unset (defaulting to `"values"`) while the mapping and the frontend were both written for
`"updates"`, so every event carried `node_id=None`/`state={}` and the persisted final result
fell back to the **initial** state. Contract tests exist:
`tests/integration/test_astream_contract.py`, `test_finish_presence.py`.

**The UI's read path**, per the comment at `:1250-1253`: `raw[node].node_outputs[node].content`
is the chat reply text.

**Persistence.** `save_execution_result` (`api/services.py:267-297`) writes Redis key
`exec:{execution_id}` as `{status, graph_id, updated_at, result, trigger}`, where `trigger`
records the `user_message` and `inputs` that started the run and is carried forward across
status updates (`:281-295`). Read back by `GET /v1/executions/{execution_id}`
(`routes_executions.py:122-127`), 404 if absent.

**Two caveats.** The persisted `result` is the **last stream event**, often an empty state
snapshot — the real per-node detail is in the worker logs (repo `CLAUDE.md`). And there is **no
TTL** on `exec:` keys — grep for `expire`/`ttl` in `api/services.py` returns nothing, so
execution records accumulate in Redis forever.

**Kicking off a run.** `POST /v1/executions` (`routes_executions.py:17-119`) takes
`{graph_id, inputs, initial_artifacts, metadata, thread_id, user_message, async_mode,
workspace_id}`. It **preflights the artifact bindings** — every `$initial_artifacts` name the
graph wires must be bound, else **422** naming the missing names (`:45-55`). Async enqueues to
TaskIQ and returns `status="queued"` immediately; sync executes in-process and maps
`GraphCompilationError`→422, `GraphExecutionError`→500.

---

## 8. Anything assuming the two graphs are the same kind of thing

**The headline: almost nothing. The boundary decision §9 draws is already the boundary the code
observes.** All thirteen files mentioning DashiBoard are in `tools/` (the integration),
`core/schema/` (a docstring crediting the pattern), or `kb/…/artifacts/index.py` (a comment
about `analysis_lineage` shape). **No node type, no loader phase, no schema rule, and no
validation gate knows what a DashiBoard pipeline is.** The pipeline travels as an opaque
`structured_data` artifact and its contents are checked by ExperimentTracking, never by me.

Five things to flag anyway, in descending order of concern.

**8.1 — `nodes` means two different things, and one inference phase matches by name.** In an
AgentGraph config, `nodes` is the graph's node list. In the dashi payload, `nodes` is the
**card** list (`remote_procedure.py:246-253`), and a function node wiring `dashiboard_train`
declares an input **literally named `nodes`** (`docs/dashiboard.md:97-99`). Same for `groups`
and `filters`.

The hazard is Phase 1 of edge inference, which matches an input to a producer **by name**
(`data_flow.py:50`): an input named `nodes` with no `from:` would auto-wire from *any* node in
the graph declaring an output named `nodes`. Today this is latent, because every documented dashi
wiring gives an explicit `from:` (which Phase 1 then skips, `:41-48`), and because a genuine
collision would more likely be reported as an ambiguity (`:59-67`) than wired wrongly. But the
name collision is real and it is exactly at the AgentGraph/DashiBoard seam. **Worth a
regression test, not an architecture change.**

**8.2 — `node_specs.py:6` invites the merge.** The module docstring reads: *"adding a node type
(e.g. a future `pipeline` node) means registering one spec, nothing else."* That is a comment
imagining a `pipeline` node type — i.e. a DashiBoard pipeline as a first-class AgentGraph node
rather than a tool call. Decision §9 says the two graphs are never unified; that sentence is a
standing invitation to the opposite, sitting in the registry's own documentation. It has not been
acted on and today the integration is correctly a *tool*, not a node type. **Recommendation:
delete the parenthetical, or replace the example with something that is not a DashiBoard
concept.** Cheap, and it stops the next person reading it as a roadmap.

**8.3 — the preflight assumes the simplest group shape.** `_dashi_preflight`
(`dashiboard.py:67-70`) reads `groups` as `{name: {cols: [...]}}` and silently skips anything
else. That is not "assuming the graphs are the same" so much as **assuming DashiBoard's variable
vocabulary is simpler than it is** — a stale model of your document, held on my side, which
decision §6 will make visibly wrong. Detail and fix in §5.6.

**8.4 — the docs describe the pipeline as "the pipeline" without qualification.**
`docs/dashiboard.md` uses "pipeline" for the card DAG and "graph" for the AgentGraph graph,
consistently — good — but `DashiTrain.nodes`'s own field description says *"The pipeline: a list
of card nodes"* (`remote_procedure.py:246-250`), and that description is copied **verbatim into
the generated tool docstring** an LLM reads (`spec.py:11-12`). An agent that has just been told
its graph has "nodes" now receives a tool whose "nodes" are something else. No bug observed; a
known source of model confusion in this class of system. **INFERRED:** I have not measured
whether it causes actual failures.

**8.5 — nothing else.** I checked specifically for: a validator that would run an AgentGraph
schema over a pipeline document (none — the config artifact's contents are only checked for
*unknown top-level keys* against `ConfigInput.fields`, `spec.py:307-312`); a loader phase that
reads inside a config artifact (none); a graph-rendering path shared with pipeline rendering
(none — we emit no DOT at all); a shared node-id namespace (none — `from_run` passes an integer
run id, not a node reference).

---

## 9. Recommendations, gathered

Changes to **this** repository that the refactor should make, in priority order. All are mine to
implement on `ds-DashiUI`.

| # | change | for | size |
|---|---|---|---|
| 1 | **`PATCH /v1/artifacts/{ref}/metadata`** → `ARTIFACT_STORE.annotate` | decision §2: the UI annotates what it saves. Currently impossible over HTTP (§3.5) | ~15 lines |
| 2 | **Merge, don't replace, when injecting enums** in `derive.py:197`/`:209` | preserves `title`/`description` on the fenced fields; unblocks decision §4 (§1.6) | ~6 lines |
| 3 | ~~Generalize `_dashi_preflight`~~ → **FREEZE it at its current narrow arms; do NOT extend it to DashiBoard's dependency grammar** (revised §5.6). Keep `id_var` and `filters[].colname` — the only coverage of those paths (§0.5.6) | replicating another system's grammar locally is a rot surface; `load_options` is the proof. **#12 carries this coverage instead**, by sending `cols` and letting ET validate | 0 lines — a decision not to |
| 4 | **CORS allowlist from env** instead of three hard-coded origins | the UI's origin must be configurable, not a literal (§3.5, decision §11) | ~5 lines |
| 5 | **`additionalProperties: false` at node level** in the designer audience, + `extra="forbid"` on `NodeConfig` | closes the silent-drop defect; six seeded configs are affected and would need fixing with it (§1.6) | small change, real blast radius |
| 6 | **`ui_path` on `RemoteServiceSpec`**, projected by `_project` | so nexus does not hard-code a path suffix onto the JSONRPC base URL (§4) | ~3 lines |
| 7 | **Structured `ValidationReport.errors`** (`{path, culprit, issue}`) and remove the `[:10]` truncation | only if a UI ever renders AgentGraph validation; not needed for the DashiBoard UI itself (§7.2) | larger; defer |
| 8 | **Delete the `pipeline` node-type parenthetical** at `node_specs.py:6` | stops a comment reading as a roadmap against decision §9 (§8.2) | 1 line |
| 13 | **Carry statically-knowable constraints in the TYPE, not in `SchemaContext`** — `TypeVar(bound=…)` + a registry per bound, measured working in §11.6 | `SchemaContext` is a *dynamic* mechanism doing a *static* job; the `designer_param_refs` scar (§1.2) is that mismatch failing. Design change, not a library feature | large; the right direction |

### 9.1 Client-side fixes from the §0.5 amendment

Item 12 is the cheapest and is unblocked (§0.5.5 RESOLVED); do it first.
These are defects, not refactor work — they are wrong today and worth fixing regardless of
whether the UI refactor proceeds. All three are mine, all small, all in
`tools/remote_procedure.py` and `tools/platform/spec.py`.

| # | change | for | size |
|---|---|---|---|
| 9 | **Call `POST api/v1/probe` with the real method name**, not `method: "validate"` | `dashiboard_validate` validates nothing today and reports the failure as a content verdict (§0.5.1). **Blocked on** the ET probe thunk returning `{source_vars, output_vars}` — without it this trades a wrong answer for an `AttributeError` | ~10 lines, after the ET change |
| 10 | **Rename `load_options` → `source_options`, add `destination_options`** | reader options are silently dropped, producing a mis-parsed table with no error (§0.5.2) | ~8 lines |
| 11 | **Distinguish `method_not_found` from a payload rejection** at the parse site | a protocol-level `JSONFailure` currently reaches an agent as `{"valid": false}`; it should raise `RemoteUnreachableError` like any other "nobody answered" (§0.5.1) | ~5 lines |
| 12 | **Add `source_metadata` to `DataFlow`; populate `cols`** from the source artifact's recorded columns | card-internal column references are unchecked end to end; ET treats an absent `cols` as unconstrained (§0.5.4). **Unblocked — the column enums ride the `$ref` target and survive draft-07 resolution, so this restores a rung that really checks (§0.5.5 RESOLVED)** | ~6 lines |

Item 11 is the general lesson, and it generalizes past this bug: **my error classification keys
on the shape of the response body (`"error"` present, `"result"` absent) rather than on the JSONRPC
error *code*.** Every server-side failure — bad payload, unknown method, internal crash — arrives
in the same shape, so the one distinction I most need to preserve is the one I cannot make. ET
already sends the codes (`method_not_found`, `invalid_params`, `internal_error`,
`ET:src/api/json_rpc.jl`); I just ignore them. **Read the code, not the shape.**

### 9.2 Asks of ExperimentTracking

Revised after §0.5 — one withdrawn, one added:

- **Structured validation errors** (`{path, culprit, issue}` rather than one prose blob).
  Unchanged, and still the highest-value item (§5.8, §7.2).
- **Make the probe thunk return `{source_vars, output_vars}`** instead of `nothing`. This
  replaces my original "add a `validate` method" ask, which is **withdrawn**: the probe route is
  the better mechanism (§0.5.1). It is also a hard prerequisite for fix #9 above.
- **Confirm whether a `source_metadata`-only probe is supported** — i.e. whether `source` and
  `destination` can be relaxed, or whether placeholder paths are the intended idiom (§0.5.3).
  This decides whether decision §2's save-time annotation needs a connected source.

---

## 10. Open questions for the other sessions

**For ExperimentTracking:** does `validate` today require a `dataflow`, or would omitting it be a
small change? That answer decides whether decision §2's save-time annotation is cheap or needs
the UI to hold a connected source.

**For nexus-weaver-pro:** if you embed by iframe, do you want the URL from `GET /v1/services`
(where it is the JSONRPC base, `http://host:8080/`) plus a convention for the UI path, or should
I add `ui_path` to the spec (§4)? I would rather add the field than have you append a suffix.

**~~For DashiBoard (schema shape, blocks my #12)~~ — ANSWERED:** the column enum is on the
`$ref` target, so it survives draft-07 resolution and #12 is a real fix. See §0.5.5.

**For the lead:** decision §6's `{selector-kind, value, through?}` repeater is the piece of this
refactor with **no precedent in my repository** (§6.5). I would not treat its resemblance to my
`from:` model as evidence that it is derisked — my model is one selector kind with one source per
input, and that poverty is exactly what makes my schema unable to drive a form.

---


---

## 11. Where Pipelines is better than `core/schema/` — the brief written the other way round

This section exists because §1–§10 were written in one direction: *"the design you are about to
attempt has already been built once, downstream, so learn from how it went."* That framing was an
accident of my brief's remit, and it did damage. It made a recommendation of mine
(§7.2 rec 3, withdrawn in §0.5.7) land as experience when it was an untested assertion, and it
led the lead session to adopt my §14 rule 1 without first checking whether it described a
mechanism DashiBoard has — it does not (11.3 below).

Content supplied by the DashiBoard session at my request. **Every claim below I re-verified in
`DashiBoard:Pipelines/` myself; the Python measurement in 11.6 is my own.** Anything I could not
check is marked.

### 11.1 The gated union has two parts beyond the gate

I described the gate and stopped there. `tagged_schema` (`structs/json_schema.jl:56-69`) carries
two more pieces, both verified:

- **`option_schema["properties"]["type"] = true`** (`:62`). Every `then` branch is a
  `composite_schema` with `additionalProperties: false`, and the variant struct has no `type`
  field — so without this line the discriminator would be rejected as an extra property *inside
  its own branch*. `true` is the always-valid schema used as a whitelist. Invisible until it
  breaks.
- **Absence-means-default, in pure JSON Schema.** `match_property` (`:172-184`): under
  `is_condition`, `is_required = !isnothing(default) && !is_match(default, x)`. The branch
  matching the default does **not** require `type`; every other branch does. So a document
  omitting the discriminator validates as the default variant, with no preprocessing step.

I have nothing equivalent to either. My variants inherit `type` from the base `NodeConfig` so the
whitelist problem never arises — but I also have no default-variant encoding, and a node omitting
`type` is simply invalid.

*(The DashiBoard session was careful to say it can attest what the code does, not that it was
reasoned to. I am recording the same caveat.)*

### 11.2 Strictness is the default, not an opt-in

`composite_schema(::Type{T}; additionalProperties::Bool = false)` (`json_schema.jl:38`) —
verified. Because every `then` branch is itself a `composite_schema`, a typo in a method three
levels down is caught. Mine is the inverse: `additionalProperties: false` appears only on
`parameters`, only for the designer audience (`derive.py:195`), and never at the node level —
which is §1.6 defect (1) and the six shipped configs silently dropping `max_tool_iterations`.

**This is my §14 rule 3 ("derive strictness, not only shape") arriving back at me. They do it;
I recommended it; I do not do it.**

### 11.3 Specialisation CONSTRUCTS; it never injects — and my rule 1 does not transfer

This is the structural answer to the presentation-metadata question, and the most important item
here. `schema_definitions(variable_config)` (`group_api/schema.jl:28-48`) builds `node`, `group`
and `col` as **fresh** `json_string(enum = …)` dicts, and `card_schema` assigns a whole new
`$defs` onto a newly built schema. **There is no injection step, so there is nothing that can
destroy `title`/`description`.** Structural, not convention.

My §14 rule 1 — *merge, never replace* — is a correct fix for **my** defect, which is that I
mutate an already-built property dict (`derive.py:197`, `:209`). It is not a rule DashiBoard
needed, and the lead reports adopting it before checking. Worse, per their analysis: at `$defs`
depth their schemas alias module constants across ~24 paths, so "merge into the existing property
dict" would have been a **process-global write leaking across requests**. Importing my fix would
have created a defect they did not have.

*(Flag CLOSED — I derived the count from source myself, and the aliasing is stronger than
"consistent with". `one_or_many_schema` does `obj_schema::StringDict = schema`
(`json_schema.jl:191-193`) — an **assignment, not a copy** — then embeds that same mutable dict
as both the object branch's `then` and the array branch's `items`, so its argument is reachable
at 2 paths. `schema_definitions` (`group_api/schema.jl:33-38`) calls it three times, passing the
**same** `item_schema` object to two of them, giving 6 reachable item-schema positions. Each
`variable_item_schema` embeds `JSON_NODE` twice — `nodes` and `through` — plus `JSON_GROUP` and
`JSON_COL` once each (`:14-19`). 6 × (2,1,1) = 12 node + 6 group + 6 col = **24**, agreeing with
their independent walk. Julia dicts are mutable reference types, so a merge through any one path
mutates all of them: the process-global write is a property of the source, not an inference from
it. The lead notes the original number was ExperimentTracking's, relayed in their own voice —
which is the thing the flag actually caught, and the more useful half.)*

The general lesson, and it is the one worth carrying out of this whole exchange:

> **A lesson from another codebase needs its MECHANISM verified in the target before its
> CONCLUSION is imported.** "Merge, never replace" is sound advice to anyone who injects. To
> anyone who constructs, it is noise at best and a new bug at worst. The authority of "we already
> built this" is exactly what stops that check from happening.

Their one real exposure here is narrower and it is A3a: `schema_from_type` (`:24-31`) writes the
derived `type`/`default` and then `merge!`s the tag over it, and nothing *enforces* that the two
write disjoint keys — they happen to, except at the `$ref` + `type` collision.

**A3a and the aliasing above are INDEPENDENT defects — do not read one as the other.** I made
that conflation in conversation and it would mislead an implementer, so, verified: A3a's
`schema_from_type(T)` opens with `schema = StringDict()` (`json_schema.jl:4`) — a **fresh** dict
per call — and `merge!` copies the tag's key-value *pairs* into it rather than embedding the tag
object. So A3a is **two conflicting keys in one private dict**; the aliasing (their A3e) is **one
mutable dict reachable from twenty-four places**. Nothing is shared in A3a and nothing collides
in A3e. Fixing either leaves the other live. The same six constants appear in both stories in
different roles — embedded as *values*, which creates the sharing; merged as *contents*, which
creates the collision.

### 11.4 Two independent gates from one declaration

A DBSCAN card naming `sqeuclidean` is rejected twice — by the schema (the `MetricMethod` enum
excludes it) and at parse by `choose_method` (`method.jl:5-16`), which raises naming the valid
metrics. Neither check knows the other exists; both descend from the single type bound
`DBSCANMethod{D <: MetricMethod}`.

My analogue is weaker and it is a *duplication*, not a derivation: `LLMParams.provider_requires_model`
(`params.py:50-56`) restates in pydantic what `_apply_context` (`derive.py:136-144`) expresses as
`if/then`. Two encodings of one rule in two languages, with nothing checking them against each
other — I flagged this myself in §2(b). Theirs are two projections of one declaration; mine are
two copies of one intention.

### 11.5 Errors are structured at source

`SingleIssue` carries `x`, `path`, `reason`, `val`, and on an enum failure **`val` is the allowed
set** — the structured-choices property I asked for in §7.2 and §0.5.8, present from the start
rather than recovered by descending into sub-errors. Mine is `list[str]`, joined and truncated
(§7.2). This is the one place my brief already said they were ahead; I am confirming it.

### 11.6 My Q4 premise was wrong — and the correction is the most actionable thing here

I wrote that the type bound "looks strictly better" than `SchemaContext`. That is wrong, and the
correction is worth more than the compliment would have been:

- **The type bound narrows STATICALLY.** Which dissimilarities are admissible under DBSCAN is
  knowable when the struct is written.
- **`VariableConfig` narrows DYNAMICALLY.** Which columns exist is knowable only per request.
  That is `SchemaContext` under another name.

**They have both. I have only the dynamic one, and use it for both jobs.** That is the real gap —
not that mine is cruder, but that constraints knowable at definition time are carried at runtime,
where they can drift from the reason they exist. My `designer_param_refs` scar (§1.2) is exactly
this: a static fact ("a designer-authored function node may only run a reviewed tool") carried as
a runtime enum lookup keyed by a type-name literal, which is why a rename could silently disable
it.

**Python can express the static half. I measured it** — pydantic exposes the bound, and
`__subclasses__` supplies the registry:

```python
D = TypeVar("D", bound=Dissimilarity);  M = TypeVar("M", bound=Metric)
class KMeans(BaseModel, Generic[D]):  dissimilarity: D
class DBSCAN(BaseModel, Generic[M]):  dissimilarity: M

KMeans.__pydantic_generic_metadata__["parameters"][0].__bound__   # -> Dissimilarity
DBSCAN.__pydantic_generic_metadata__["parameters"][0].__bound__   # -> Metric
```

```
KMeans   offers -> ['Euclidean', 'Cosine', 'SqEuclidean']
DBSCAN   offers -> ['Euclidean', 'Cosine']
```

Different options per card, from the bound alone, no extra declaration — the same property Julia
gets from dispatch. What I would additionally need is their registry-per-bound convention, so
this is a design change rather than a library feature. **Recommendation #13.**

### 11.7 The defect we share, which my question surfaced

`validate_pipeline_schema` (`group_api/schema.jl:71-99`) validates `node["card"]` and each group
— **never the node wrapper**. Verified. `Node(d)` (`node.jl:66-74`) reads `d["card"]` and `get`s
`id`/`label`/`train`/`state`, ignoring everything else. So `[[nodes]] id = "x", trian = false` —
a typo for `train` — passes validation, is silently dropped, and the node trains anyway.

That is my §1.6 defect (1) exactly, in their repository. Mine was documented; theirs was not,
until my question made them look. **Honest scoreboard on strictness: they are better one level
down (11.2) and identical to me at the top.**

### 11.8 Where I am better, and they are taking it

Recorded for symmetry, and because both are cheap:

- **Fail-soft enums, fail-closed gate.** An empty enum does not constrain (`derive.py:22`), but
  the registry *refuses* a `status='valid'` write when the context cannot be built at all
  (`registry.py:120-127`). Theirs is the opposite and it is the mechanism behind §0.5.4:
  `VariableConfig` treats `nothing` as *unconstrained*, so an omitted `cols` means every column
  reference validates and the failure lands later as a SQL error.
- **The `audience` mechanism.** One derivation, two strictnesses, selected by a string. They have
  one strictness for every consumer, and will want this once the schema serves both a browser and
  a stricter save path.

### 11.9 What this section changes about reading §1–§10

Nothing factual — no claim in §1–§10 is retracted here beyond the three already retracted in
§0.5. What changes is the register. §1.6's "which parts of this design have worked" is an honest
account of *my* implementation, and where it reports pain, the pain is real. But **a defect of
mine is not evidence that DashiBoard has the same defect**, and three times in this exchange it
was read that way — rule 1 (they construct, so it does not apply), rec 3 (their union shape was
right), and the `anyOf` diagnosis (my nullable wrapper, not the union).

Read §1–§10 as a case study of one implementation's failure modes, not as a specification for a
better one. Where the two overlap — rules 2, 3 and 4 of §14, the positional-semantics amendment,
the `designer_param_refs` scar — they overlap because the mechanism was checked, not because the
source was authoritative.

---

*Written by the AgentGraph session, 2026-08-31, §11 added 2026-09-01, against `ds-DashiUI` at `ae27633`. Available for
follow-ups.*
