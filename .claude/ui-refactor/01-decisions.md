# 01 — What has been decided

The settled specification for the DashiBoard UI refactor, agreed with the project owner.
This is the binding document: do not propose anything that contradicts it without saying so
explicitly and giving your reason.

Read `00-dashiboard-context.md` for what the code does today, and `02-stack.md` for how the
four projects relate.

---

## 1. Goals

**Collapse the duplicated card description.** The card UI is derived from the annotated
Julia struct, exactly as the JSON Schema already is. The hand-written second description
goes away.

**Make the UI standalone and embeddable.** It runs on its own, served by Julia, as the
primary way to use DashiBoard. It is also embeddable in nexus-weaver-pro's DashiBoard menu,
replacing the mocked `src/pages/DashiboardPage.tsx`.

**Scope covers four repositories.** Changes to ExperimentTracking, AgentGraph and
nexus-weaver-pro are in scope alongside DashiBoard. None of them is a fixed constraint to
design around; where a change to one of them is the right answer, it is available.

---

## 2. The document the UI produces

The UI produces an **ExperimentTracking `Config`** — `{filters, nodes, groups}`. Not a bare
Pipelines pipeline document.

That single document is simultaneously:

- what ExperimentTracking runs, given a `DataFlow`;
- what an AgentGraph node loads as its `pipeline_artifact` — `ConfigInput` declares
  `fields=("nodes", "groups", "filters")`, the same three keys
  (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:186`);
- what the UI saves, imports and round-trips.

**Round-tripping means the stored JSON, never a reconstruction from `Card` objects.** By the time
Cards exist the group vocabulary has been resolved away — `inputs` comes back as `["PRES","TEMP"]`
rather than `{cols = [...]}` — and `StructUtils.lower` emits `null` for nullable fields whose schema
does not permit null, so a document rebuilt that way is invalid on two counts. The authored JSON in
the registry's `Config` is the only copy of the document form. This is a trap for anyone building
"export the current pipeline".

**The end user never hand-writes it.** Importing an existing config is supported as a way to
start a draft from a previous pipeline and adapt it, not as the normal route in.

**The document carries no `DataFlow`.** Source and destination are bound per invocation:
by "Connect source" when running standalone, by the calling node when embedded. So the saved
document is source-agnostic, and "Connect source" during authoring exists to supply column
names, not to be persisted.

**The UI annotates what it saves.** AgentGraph's preflight is built to read
`content_metadata["required_columns"]` off the config artifact and compare it against the source
table's recorded columns (`dashiboard.py:74-84`). Note that this path exists but has never fired:
only `dashiboard_validate` writes that annotation, and it calls a method ExperimentTracking does
not serve. Treat it as the contract to satisfy, not as a safety net already in place. The UI produces that annotation from
the server's own dependency analysis before saving.

Two things this needs that do not exist yet, both confirmed in reconnaissance:

- **ExperimentTracking `main` has no `validate` method.** It serves four methods and answers
  "validate without executing" with a *route* — `api/v1/probe` runs each handler's validation
  phase and discards the resulting thunk, returning `null`. That is a better mechanism than a
  separate method, because it applies to every method present and future with no second
  validator to drift. The change is to have the probe thunk return `{source_vars, output_vars}`
  rather than `nothing`; ~25 lines. (An earlier draft of this document cited a `validate` method
  returning exactly that shape — those citations were against the unmerged branch
  `ds/file-mode-and-run-events`, not `main`.)
- **No HTTP route writes `content_metadata`.** Today `required_columns` is computed and attached
  by `dashiboard_validate`, an AgentGraph *tool*, inside the worker process. A browser cannot do
  it. AgentGraph must expose a route that annotates an artifact.

**Only the `cols` vocabulary was ever unvalidated.** `nodes` and `groups` are checked with or
without `source_metadata`, because `validate_pipeline_schema` derives them from the document itself
via `get_id.(nodes)` and `keys(groups)` — a dangling node or group reference has always been
rejected. Measured through the probe: supplying `cols` turns ACCEPT into REJECT for a bad column in
a card's `inputs`, in a card's `group_by`, and in a group definition.

**Two paths remain uncovered even so**, and the client-side checks that currently cover them must
not be retired as redundant: **a filter naming a nonexistent column**, because `initialize_filters`
ignores its `DataFlow` and no filter schema exists, and **`id_var` not among the columns**, because
it is a `DataFlow` field and never reaches `validate_pipeline_schema` at all. AgentGraph's preflight
on `id_var` and `filters[i].colname` is presently the only coverage either has. It stays until
section 8's filter schema lands, and `id_var` stays uncovered even then unless something checks it
against `source_metadata["cols"]`.

**Validating a source-agnostic draft is largely already possible.** The saved document carries no
`DataFlow`, so a UI authoring one has no connected source to validate against — which looked like
a gap. It mostly is not: `DataFlow.source_metadata["cols"]` is documented in place as "a list of
available column names, used to validate the pipeline"
(`ExperimentTracking:src/entries.jl:121-122`), and `initialize_pipeline` already branches on it,
passing those columns into `Pipeline(c.nodes, c.groups, cols)` (`entries.jl:130-134`). So a client
hands the server the column *names* it is authoring against rather than a readable table, and gets
back a real validation. This is also mandatory rather than optional: `VariableConfig`'s fields
treat `nothing` as *unconstrained*, not empty, so omitting `cols` yields a schema with no column
enum at all and a card referencing a nonexistent column passes validation, failing only at SQL
execution.

**How to validate without a source, today: pass `""` for `id_var`, `source` and `destination`.**
The validation phase never reads them — `execute_handler`'s validation phase is five statements and
the only `DataFlow` field any of them consults is `source_metadata["cols"]`. Verified through the
real probe route: omitting the three fields is rejected `-32602`; empty strings are accepted; a
wrong column in a group is still rejected with a pointer (`"path: [cols][1]"`); a placeholder path
at `/nonexistent/nope.parquet` is accepted; and the probe writes nothing — zero registry rows, empty
weights directory.

**The three fields must not be relaxed.** They are the only thing making a malformed *train*
fail as `-32602` before any work happens. Making them optional moves that failure to `-32603`, deep
in SQL after selection has run, and collides with the registry, where `Column(:source, "VARCHAR")`
is NOT NULL — so a null source would fail at INSERT and an execution-phase check would have to be
re-added anyway. That is weakening the real path to serve the probe path.

**Placeholders are interim; the destination is a document-level method.** `""` conflates two
questions: "would this whole request run?", which legitimately needs a real `DataFlow` and should
stay strict, and "is this document well-formed against these column names?", which has nothing to
do with a data flow. The authoring UI only ever asks the second, and should not have to invent a
source to ask it — a magic `""` is undiscoverable and one copy-paste away from reaching `train`,
where an empty destination names a table `""`. The answer is a method taking
`{nodes, groups, filters, cols}` and returning `{valid, source_vars, output_vars}`, constructing no
`DataFlow` at all. It calls the same `initialize_filters` and `initialize_pipeline`, so it is a
second *caller* of one validator rather than a second validator — the drift risk that sank the
earlier `validate` method does not arise.

**Consuming `source_vars` correctly.** It is the union of every `{cols = [...]}` selector, not
"columns present in the source" — a card naming another card's output via `cols` lands in it too,
so a client must subtract `output_vars`. And `id_var` is not included; a UI computing
`required_columns` must union it in itself.

---

## 3. How card UI is derived

**Where the boundary sits.** The annotated Julia struct is the *source*; what crosses the wire is
the *contract*; the browser sees only the contract and has no knowledge of Julia. "Type" below means
a node of the emitted contract — an object description, or a named variant — not a Julia type. The
Julia types are what the contract is derived from, one layer earlier, at request time. Nothing is
generated at build time, because the contract is specialised per pipeline: which columns a card may
reference depends on which upstream cards the user added seconds ago.

**A UI component is derived from a type, and must be renderable from that type alone.** No
ambient scope, no ancestor state passed down.

- A scalar field becomes a leaf widget built from its `dashi` constraints.
- A field whose type is an abstract union becomes a type-selector plus the selected
  variant's own component, rendered inline.
- Nesting is genuine: `ClusterCard` → `KMeansMethod` → `WeightedMinkowskiMethod` is three
  real levels.
- A selector's options come from the **field's type bound**, so `KMeansMethod{D <:
  DissimilarityMethod}` offers all nine dissimilarities and `DBSCANMethod{D <: MetricMethod}`
  only the seven true metrics. No extra declaration needed.

**Cross-level constraints are validation, not rendering.**
`WeightedSqEuclideanMethod.weights` must match the card's `inputs` in length and order, but
the weights widget does not know that and renders as a plain array-of-numbers input. The
mismatch is caught by `validate_pipeline_schema` and surfaced as a `SchemaValidationError`.
The error contract to the UI therefore matters: it is the only place some constraints become
visible.

**Dynamic enums are baked server-side.** The available `nodes`, `groups` and `cols` are not
computed in the browser — that would be ambient scope. They are injected into `$defs` by
`card_schema(key, variable_config)` before the schema reaches the UI, which therefore
receives a schema already specialised to the current pipeline state.

**This removes** `method_dependent_widgets` and its dotted `method_options.dayofyear.max`
keys (`Pipelines/src/widgets.jl:64-81`). That flattening existed only because the model had
no nesting.

**Positional constraints do not demote.** The demotion above is safe only when a constraint is
about a field's *value*. `WeightedSqEuclideanMethod.weights` must match the card's `inputs` in
length **and order**: the length half demotes cleanly to a validation error, the order half does
not, because every ordering is valid and one is merely the intended one. There is no invalid
value to report. Rules of that shape must be designed out, not demoted — either by marking the
governing field unordered so no widget offers reordering, or by changing the representation so
correspondence is explicit rather than positional. AgentGraph shipped a rule of this shape (their
finish tool is named after `outputs[0]`) and reports that it went badly and stayed badly.

---

## 4. Where presentation metadata lives

**In the `dashi` tag**, using JSON Schema's own keywords. Label from `title`, help text from
`description`.

**Field order is a separate problem, and it is currently lost.** `composite_schema` iterates
`fieldnames(T)` in declaration order but writes into a `StringDict` — a plain `Dict{String,Any}`,
which is unordered — so struct order does not survive schema generation at all. Measured on
`GaussianEncodingCard`: declared `[method, input, n_components, lambda, suffix]`, emitted
`["method", "suffix", "lambda", "input", "type", "n_components"]`. No relation. **The IR carries
order structurally**, as an ordered array in declaration order — which is why section 13 splits the
two artefacts rather than annotating order onto the schema. The work is to *capture* an order that
is presently discarded, not to preserve one that survives. Widget kind is inferred from the JSON type
plus constraints: enum → select, array of enum → multi-select, bounded number → spinner,
boolean → toggle. The `json_string`/`json_number`/`json_array` helpers already accept `title`
and `description` (`Pipelines/src/structs/json_schema.jl:90-137`), so no new vocabulary is
introduced.

**This deletes** every `Pipelines/assets/config/*.toml` and every per-card `CardWidget`
method. Adding a card becomes a single annotated struct definition.

There is deliberately **no override** when the inference picks the wrong widget. If that
bites, revisit it as a decision — do not quietly reintroduce a sidecar file.

**One shape defeats inference: the free-form map.** `groups` is `{name: {cols|nodes|groups,
through}}` — an object with `additionalProperties`, which no rule turns into a usable widget
because the value editor depends on what the map is *for* and the type does not say. Section 6's
purpose-built picker is the answer. The renderer dispatches on a `$ref` to a named `$def`, which
is **type identity, not a widget override** — exactly what section 3 already says components
dispatch on — so the no-override rule survives intact. The seam is deliberate, not a loophole.

---

## 5. The canvas

Three buttons: **Connect source**, **Add group**, **Add node**.

The canvas renders the inferred graph under **automatic layout**, and clicking a node opens
its form in a side panel. **No node positions are stored anywhere** — the layout is a pure
function of the document, and nothing UI-only enters it.

Users cannot draw edges. Edges are inferred from what each node consumes
(`Pipelines/src/dag.jl:30-56`).

The Graphviz output needs updating from its current bipartite card-and-variable form to the
node + group vocabulary.

---

## 6. Groups and the variable picker

**"Add group" exposes the full variable vocabulary**, reusing the same component that renders
any card's `JSON_VARIABLE` / `JSON_VARIABLES` field. One picker, two levels.

It must offer:

- a **selector kind**, exactly one per item: `cols`, `nodes` or `groups`;
- an optional **`through`** qualifier on any of the three;
- a **repeater**, because a group is one item or a list, and a list is a union.

See `00-dashiboard-context.md` for the semantics of each.

---

## 7. Scope of the frontend work

**The whole frontend is rebuilt.** The canvas replaces the left tabs entirely: "Connect
source" subsumes Load, and filtering stops being a separate panel. The result panes —
Spreadsheet, Visualization, Graph — are rebuilt rather than ported. One app, one rendering
mechanism.

This retires `frontend/src/left-tabs/`, `frontend/src/right-tabs/`, `frontend/src/filters/`
and the `{filters, cards}` request shape assembled at `frontend/src/App.jsx:49-52`.

---

## 8. Filters

**Filters are unified in the canvas but stay a top-level key in the document.** The canvas
presents them as nodes; the emitted `Config` keeps `[[filters]]` exactly where
ExperimentTracking already puts it. No `Config` schema change and no registry migration.

Their UI is derived from `DataIngestion`'s `Filter` structs under section 3 — but that
mechanism does not reach them yet, and building it is **1–2 days of Pipelines/DataIngestion work**
that must be budgeted. `DataIngestion` does not depend on StructUtils, so `composite_schema`
cannot be pointed at a `Filter` at all; there is no `CARD_SPECS` equivalent, so a UI cannot even
enumerate the filter types; `type` is a discriminator that is not a struct field; and
`ClosedInterval` matches no branch of `schema_from_type`, deriving to an empty, entirely
unconstrained schema. `ListFilter{T}` narrows `T` from its data, so there is no static type to
derive `items` from.

What it needs is what cards already have, built once: a spec registry, StructUtils annotations
(either DataIngestion gains the dependency, or the schemas are defined in Pipelines where the
machinery lives — **this is an open call**), a tagged-union schema over `FILTER_TYPES`, and a
hand-written sub-schema for the interval shape. Plus a `filters` wire method.

The data-derived half **is** free: `DataIngestion.summarize` already returns `{min, max}` for
numerical columns and unique-sorted values for categorical ones — precisely the two shapes the two
filter types need.

Filters are **not** cards. They subset rows — `DashiBoard/src/handlers.jl:22-27` materialises
a `selection` table before the pipeline runs — whereas a Card produces columns and `evaljoin`
joins results back on `_id`. A row-dropping card would break that join.

Filter widgets are data-derived: the interval filter's bounds come from the column's own
min/max. Under section 3 those bounds are baked into the schema server-side, like the dynamic
enums.

Filters are also never validated today. `initialize_filters` ignores its `DataFlow` argument
(`ExperimentTracking:src/entries.jl:128`, carrying a `# TODO: use DataFlow to validate filters`),
and `validate_pipeline_schema` receives only nodes, groups and cols. A filter naming a nonexistent
column therefore fails at SQL execution as an internal error rather than as a form error.
Implementing that TODO belongs with the filter schema work.

---

## 9. How the three layers fit together

1. **DashiBoard has a standalone UI.** It is the base, usable on its own.
2. **ExperimentTracking reaches to it** and builds its additional capabilities — registry,
   run lineage, multi-pipeline orchestration — on top of that UI.
3. **nexus-weaver-pro embeds it** in its DashiBoard menu, through the `RemoteService`
   connection AgentGraph already defines.

This is layering, not replacement, and it follows the grain of the code: the package
dependencies already run ExperimentTracking → Pipelines.

**AgentGraph's graph and DashiBoard's graph are never unified.** From AgentGraph's side,
DashiBoard is one step inside one node; that step's internal pipeline DAG is opaque to it.
Nothing in this refactor tries to make one graph out of the two.

**The RemoteService layer carries the URL, not the traffic.** `GET /v1/services` returns each
registered service's resolved connection with per-field provenance;
`PUT /v1/services/{service}/connection` overrides `url` and `timeout`;
`GET /v1/services/{service}/health` runs the spec's own `discover()` probe
(`agentgraph:src/agentgraph/api/routes_services.py`). The only call AgentGraph makes on that
connection is `discover()`. **AgentGraph is a directory, not a proxy** — an embedded UI's own
API calls go browser → Julia directly.

---

## 10. Serving and origins

**ExperimentTracking serves the UI's static assets** alongside `POST api/v1`, so the app and
the API share an origin by construction: no cross-origin permission headers, no separate auth
plumbing, one process and one port.

**ExperimentTracking has no CORS handling at all** — two response headers, no
`Access-Control-Allow-Origin`, no `OPTIONS` route, no preflight support. That is fine for the
same-origin production case above, but it blocks development immediately: a Vite dev server on
another port makes every JSON `POST` a preflighted cross-origin request, and every preflight fails
against a router with no `OPTIONS` route. CORS must be added as *configured* middleware — an
explicit origin allow-list parameter defaulting to none — not as an unconditional wildcard.

This composes with an iframe embed for nothing — an iframe whose `src` is the resolved
RemoteService URL is same-origin inside the frame. A React-component embed would put the code
on nexus-weaver-pro's origin instead, bringing cross-origin configuration back regardless of
what the Julia side does. That inclines the embedding question toward an iframe; it does not
settle it.

**One narrowing on the iframe, reported by the nexus-weaver-pro session (2026-09-09).** An
`<iframe src>` cannot carry an `Authorization: Bearer` header, but it does carry cookies subject to
`SameSite`, and same-origin serving is exactly the case where a `SameSite=Lax` session rides along
without ceremony. So this plan is unaffected while the asset route is unauthenticated — the status
quo there — or under a cookie session. The one combination to design away from is bearer-header auth
*on the static asset route itself*.

---

## 11. Keep every mechanism replaceable

This is unfamiliar ground for the project owner, so mechanism choices must stay adaptable.

The concrete requirement, cheap now and expensive to retrofit: **the frontend takes its API
base address at runtime, never as a build-time constant.** One bundle then works served by
Julia (same origin, relative URLs) and served from anywhere else (absolute URL, CORS
configured), and changing that is configuration rather than a rebuild.

Apply the same test to every other mechanism choice: prefer the option that can be changed
later without re-authoring the UI.

---

## 12. Still open

Reconnaissance answered most of what stood here. What remains needs a decision from the project
owner, not more investigation.

- **Visualization: server-rendered or client-side?** The rebuilt Visualization pane can render
  Makie SVG server-side, as `evaluate-pipeline` does today, or client-side from data. It decides
  whether retiring the DashiBoard server makes ExperimentTracking inherit `CairoMakie` and
  `AlgebraOfGraphics` — a real regression for the fast-starting RPC server AgentGraph depends on.
  ExperimentTracking recommends client-side and notes the call is not theirs. **This blocks the
  retirement commit, nothing earlier.**
- **Where the filter annotations live.** DataIngestion gains a StructUtils dependency, or Pipelines
  gains a `FILTER_SPECS` table. Section 8.
- **The positional `weights` rule.** Section 3 requires it designed out. Marking `inputs` unordered
  is the cheap answer; changing the representation so correspondence is explicit is the thorough
  one.

### Settled by reconnaissance

- **The group-vocabulary schema already exists.** `schema_definitions(::VariableConfig)` is
  implemented and in use; ExperimentTracking simply constructs a flat variable list and serves the
  wrong dialect. The only callers of `schema` are its own tests and demo script, so changing it
  breaks nobody.
- **The embedding mechanism is an iframe**, pointed at the resolved `dashi` RemoteService URL with
  a `postMessage` contract. nexus-weaver-pro recommends it knowing it frees DashiBoard's framework:
  **SolidJS can stay.** Their decisive argument is that the DashiBoard URL is already a runtime,
  user-editable value through `/v1/services`, so pinning it at build time would make the one part
  of that relationship compile-time in an app that already has a first-class UI for changing it
  live.
- **The node inspector is ruled out, and the framework is settled.** It was asked as a flip
  condition in `05-nexus-weaver-brief.md` §2c — deliberately, to be ruled out cheaply before the
  framework was fixed, never as an inferred requirement. **The project owner ruled it out on
  2026-09-09.** The decisive argument, reported and verified by the nexus-weaver-pro session, is
  structural rather than a matter of product intent: `ChatWidget` builds its context from exactly
  three sources — router state, a static per-route string, and app-level globals — and its `useMemo`
  dependency array carries **no page component state, for any page**
  (`nexus-weaver-pro:src/components/ChatWidget.tsx:225-228`). No mechanism exists by which any page
  publishes state to that widget, so an inspector would need plumbing that app has never had for any
  surface. **SolidJS stays.** The iframe recommendation stands independently of this: it rests on the
  `dashi` URL already being a runtime, user-editable value with a first-class UI for changing it
  (`nexus-weaver-pro:src/lib/api.ts:1035-1067`, `src/components/ConnectionPanel.tsx:148-149`), which
  no part of that repository's DashiBoard demo scaffolding affects.
- **`pass_through` semantics** are unchanged and remain a backend TODO. The picker is unaffected.

---

## 13. The wire contract: two artefacts from one traversal

The server emits **two** documents per request, both produced by a single walk of the annotated
structs: a **JSON Schema** for validation, and an **intermediate representation** for rendering.
The frontend validates with the first and builds widgets from the second.

This is not the duplication the refactor exists to remove. `CardWidget` and the schema drift because
they are *authored* separately by hand; these two are emitted by the same traversal, so a divergence
is a bug in one function rather than two hand-maintained descriptions falling out of step.

### Why they are separate: measured error quality

The alternative — one JSON Schema document carrying `x-dashi-*` extensions for the renderer — forces
the union into `oneOf`, because a renderer needs a discriminated lookup rather than trial
validation. That trade costs error quality, and the cost is large. Measured with Ajv 8 on a
`{kmeans, dbscan}` union, instance `{type: "kmeans", classes: 0}` where `classes` must be `>= 1`:

| shape | errors reported |
|---|---|
| `oneOf` | `/classes minimum: must be >= 1`, **plus** `required: 'radius'`, `additionalProperties`, `/type const`, and `must match exactly one schema in oneOf` |
| `allOf` + `if`/`then` behind an enum gate | `/classes minimum: must be >= 1` |

On a bogus discriminator the gap is worse: `oneOf` yields five errors, none of which names the valid
types, while the gated `if`/`then` yields exactly one — `/type enum: must be equal to one of the
allowed values`.

**So the validation schema keeps the shape `tagged_schema` already emits**: `match_property` puts an
enum gate on the discriminator first, then `allOf` of `{if, then}` per variant. Check the type is
valid, then check the branch it selects. Nothing contorts it for a renderer's benefit, because the
renderer has its own document.

### The IR

An ordered array of field entries, one per struct field, in declaration order. A leaf entry carries
its `id`, `title`, `description` and the `dashi` constraints. A union entry carries its `id`, the
`discriminator` and `conditional_schemas` keyed by variant name, each value being an IR in turn.
Order is structural rather than annotated, variants are a keyed lookup rather than a `$ref`
traversal, and a renderer can switch exhaustively with no fallthrough to a JSON textarea.

Two properties it must have, and neither is optional:

- **`additionalProperties`/`required` equivalents travel with it.** AgentGraph applied strictness at
  only some levels and six of their configs silently ignored a setting for months. The IR describes
  what is required as well as what is renderable.
- **Its addressing lines up with the schema's JSON Pointers**, or a validation error cannot be
  attached to the widget the IR built. This is the seam most likely to be got wrong.

### The validation schema

- `dialect: "dashi/1"` — the client refuses unknown majors.
- **The `$ref` siblings must go, and pinning `$schema` is not a substitute.** **The sibling half is resolved as of 2026-09-09 — see the closing note. The `$schema`/`dialect` pin is still open.**
  `schema_from_type` merges a `dashi` tag into the derived schema, so
  `input::String & (dashi = JSON_VARIABLE,)` emits `{"type": "string", "$ref": "#/$defs/variable"}`,
  and `order_by::Vector{String} = String[] & (dashi = JSON_VARIABLES,)` adds a `default` sibling
  too. Under the flat dialect the target is also a string, so the sibling agrees and nothing shows.
  Under the group dialect the target resolves to an object/array, and the field must be a string
  *and* an object at once.

  Measured with Ajv 8, `$ref` alone validates and `$ref` plus the derived `type` sibling does not —
  **under draft-07 mode as well as 2020-12**, because modern JS validators apply siblings
  regardless of declared draft. Only a validator implementing the literal draft-07 replace rule,
  as JSONSchema.jl does, hides this. So pinning the draft buys determinism but would give false
  confidence if taken as the fix: **stop emitting `type` and `default` beside a `$ref`.** Five
  fields carry a discardable `default` today — `window_function.jl:28`, `split.jl:54-55`,
  `rescale.jl:111,113`. Fields defaulting to `nothing` emit no `default` at all, since
  `schema_from_type` skips it.

  **Resolved by the team leader's IR rewrite, verified 2026-09-09.** `schema_from_type` no longer
  exists — the IR replaced it. `merge_IR` discards the type-derived IR whenever the `dashi` tag is a
  `ReferenceIR` (`DashiBase/src/auto_IR.jl:7`), so a `$ref` is now emitted alone. Probed on both a
  required field and a defaulted one: `{"$ref": "#/$defs/variable"}` and
  `{"$ref": "#/$defs/variables"}`, single-key in both cases. The measurement above is retained
  because it is the reason not to reintroduce siblings, not because the defect is live. **Still open:
  nothing emits `$schema` or a `dialect` key anywhere in Pipelines, DashiBase or DashiBoard**, so the
  determinism half of this item is untouched and the client cannot yet refuse an unknown major.
- **The union shape stays as `tagged_schema` emits it** — enum gate on the discriminator, then
  `allOf` of `{if, then}`. See the measurement above. Do not migrate it to `oneOf`.
- **`additionalProperties: false` at every authored level.**
- **Errors addressed by JSON Pointer**, with a `related` array. Section 3 makes some constraints
  visible only as errors, so an error that cannot point at a field cannot be rendered next to one —
  and a `weights`/`inputs` mismatch must be able to mark both ends. `if`/`then` reports one line of
  noise (`if: must match "then" schema`) beside the real error, so the contract needs a rule for
  which to surface — deepest path wins.
- **Variants may stay inlined.** Moving them into `$defs` + `$ref` was proposed to give a renderer
  variant identity — so it could tell that the `sqeuclidean` under `KMeansMethod` and the one under
  `DBSCANMethod` are the same component. The IR's keyed `conditional_schemas` supplies that
  identity instead, so the restructure is no longer required. Payload was never the argument:
  measured, the whole nine-card response is 44 KB.

**What the IR removes from this list.** Labels, field order and discriminated lookup are the IR's
job now, so the schema needs no `oneOf: [{const, title}]` in place of `enum`, no
`x-dashi-discriminator`, and no `x-dashi-order`.

---

## 14. Rules taken from AgentGraph's implementation

AgentGraph built this design first, from Pipelines' own pattern. Four rules from their post-mortem,
each with a measured failure behind it.

1. **Construct, never annotate.** AgentGraph's version of this rule is "merge, never replace" —
   injecting a constraint by overwriting a property drops its `title` and `description`, and they
   measured two fields rendering as bare unlabelled controls, the two whose meaning most needed
   explaining.

   **Their rule does not transfer, and importing it would have caused harm.** It describes an
   injection step we do not have: `schema_definitions` *constructs* each vocabulary fresh and
   `card_schema` assigns a whole new `$defs`. Had we adopted "merge into the existing property dict",
   we would have written into objects that are shared — at `$defs` depth our schemas alias module
   constants across 24 paths, so such a write is process-global and leaks into every later request
   for every pipeline (measured; A3e).

   So the rule for this codebase is the stronger one their experience implies: **build each node
   complete and never write into a built schema.** That preserves labels for the same reason theirs
   was meant to, and it makes the aliasing unreachable rather than merely avoided.
2. **Make nullables actually nullable.** `type: ["string", "null"]`, with any enum at the same
   level. This has two payoffs and the second is the live one. AgentGraph's is diagnostic:
   `anyOf: [T, null]` makes every violation read *"is not valid under any of the given schemas"* —
   no enum named, no options listed. Ours is a correctness bug already present: `KMeansMethod.seed`
   emits `{"minimum": 0, "type": "integer"}`, permitting no null, while `StructUtils.lower` writes
   `seed: null` — so a card serialised by the writer fails validation against the schema the same
   codebase generates. The schema is internally consistent (a card seeded from its own defaults
   validates); the inconsistency is between schema and serialiser.

   **Half of the diagnostic problem is rendering, not schema shape**, and that half is fixable
   today. The enum is not lost inside an `anyOf` failure — validators keep it as sub-errors.
   Measured with Ajv 8 on `anyOf: [{enum: [...]}, {type: "null"}]` against a bogus value, three
   errors come back: the `enum` failure carrying `params.allowedValues` as **structured data**, the
   `type: null` failure from the other branch, and an `anyOf` summary. Rendering the summary and
   discarding the rest is what produces the useless message. So a UI can show the real reason before
   any schema change lands. It does not retire this rule — a schema that needs no workaround beats
   one that does — but it decouples the two.
3. **Derive strictness, not only shape.** They applied `additionalProperties: false` to the
   parameters object only; six of their configs have been silently ignoring a node-level setting,
   through a schema layer whose entire purpose was to prevent that.
4. **Watch diagnostics, not rendering, as nesting deepens.** Their discriminated union exists at
   exactly one level and everything below it is fixed structure — they never attempted
   variant-selection at depth, so they cannot confirm it works. What they can report is that error
   quality degrades with the number of union branches a validator considers. At three levels of
   nested unions, diagnostics is the thing that will hurt.
