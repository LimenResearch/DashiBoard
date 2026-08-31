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

**The end user never hand-writes it.** Importing an existing config is supported as a way to
start a draft from a previous pipeline and adapt it, not as the normal route in.

**The document carries no `DataFlow`.** Source and destination are bound per invocation:
by "Connect source" when running standalone, by the calling node when embedded. So the saved
document is source-agnostic, and "Connect source" during authoring exists to supply column
names, not to be persisted.

**The UI annotates what it saves.** AgentGraph's preflight reads
`content_metadata["required_columns"]` off the config artifact and compares it against the
source table's recorded columns (`dashiboard.py:74-84`). That is the same dependency analysis
ExperimentTracking's `validate` returns as `source_vars`, so the UI produces it by calling
`validate` before saving.

---

## 3. How card UI is derived

**A UI component is derived from a type, and must be renderable from that type alone.** No
ambient scope, no ancestor state passed down.

- A scalar field becomes a leaf widget built from its `dashi` constraints.
- A field whose type is an abstract union becomes a type-selector plus the selected
  variant's own component, rendered inline.
- Nesting is genuine: `ClusterCard` → `KMeansMethod` → `WeightedMinkowskiMethod` is three
  real levels.
- A selector's options come from the **field's type bound**, so `KMeansMethod{D <:
  DissimilarityMethod}` offers all nine dissimilarities and `DBSCANMethod{D <: MetricMethod}`
  only the six true metrics. No extra declaration needed.

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

---

## 4. Where presentation metadata lives

**In the `dashi` tag**, using JSON Schema's own keywords. Label from `title`, help text from
`description`, form order from struct field order. Widget kind is inferred from the JSON type
plus constraints: enum → select, array of enum → multi-select, bounded number → spinner,
boolean → toggle. The `json_string`/`json_number`/`json_array` helpers already accept `title`
and `description` (`Pipelines/src/structs/json_schema.jl:90-137`), so no new vocabulary is
introduced.

**This deletes** every `Pipelines/assets/config/*.toml` and every per-card `CardWidget`
method. Adding a card becomes a single annotated struct definition.

There is deliberately **no override** when the inference picks the wrong widget. If that
bites, revisit it as a decision — do not quietly reintroduce a sidecar file.

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

Their UI is derived from `DataIngestion`'s `Filter` structs under section 3, so nothing about
them is hand-written.

Filters are **not** cards. They subset rows — `DashiBoard/src/handlers.jl:22-27` materialises
a `selection` table before the pipeline runs — whereas a Card produces columns and `evaljoin`
joins results back on `_id`. A row-dropping card would break that join.

Filter widgets are data-derived: the interval filter's bounds come from the column's own
min/max. Under section 3 those bounds are baked into the schema server-side, like the dynamic
enums.

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

This composes with an iframe embed for nothing — an iframe whose `src` is the resolved
RemoteService URL is same-origin inside the frame. A React-component embed would put the code
on nexus-weaver-pro's origin instead, bringing cross-origin configuration back regardless of
what the Julia side does. That inclines the embedding question toward an iframe; it does not
settle it.

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

These are for the briefs to answer, not for the lead session to guess.

- **The five orphaned capabilities.** Source browsing, file loading, paged data fetch,
  processed-data download and DAG rendering exist only on the DashiBoard server and have no
  ExperimentTracking counterpart. Whether they move, or stay and are layered over, is open —
  and with it, whether the `DashiBoard` package survives as a server at all.
- **The schema dialect gap.** `schema_handler` passes `vars::Vector{String}`
  (`ExperimentTracking:src/api/handlers.jl:138-145`), which reaches the flat
  `schema_definitions(::AbstractVector)` rather than the `VariableConfig` method in
  `group_api/schema.jl`. The schemas served today cannot express `{nodes|groups|cols,
  through}` at all, and section 6 requires that they can.
- **The embedding mechanism**, and with it the frontend framework. If nexus-weaver-pro wants
  a React component, DashiBoard's standalone UI is React too. If an iframe, the framework is
  free.
- **`pass_through` semantics.** Marked `# TODO: more general definition`
  (`Pipelines/src/group_api/deps.jl:98`). Backend work; the picker is unaffected either way,
  since it only chooses node ids.
