# 00 — DashiBoard as it stands today

Factual description of the DashiBoard monorepo before the refactor. No decisions here —
those are in `01-decisions.md`. The other three projects are in `02-stack.md`.

Line numbers are against DashiBoard `main` at commit `e6f4794`.

## Packages

`/home/dariosarra/Documents/Limen/DashiBoard` is a Julia monorepo implementing a
data-pipeline GUI over DuckDB.

| Package | Role | Depends on |
|---|---|---|
| `DuckDBUtils` | `Repository`, FunSQL rendering, table helpers | — |
| `DataIngestion` | readers, `Filter` types, `select` (row subsetting) | DuckDBUtils |
| `StreamlinerCore` | ML training, behind `StreamlinerCard` | DuckDBUtils |
| `Pipelines` | `Card`, `Node`, the DAG, `CARD_SPECS`, schema derivation, widgets | DuckDBUtils, StreamlinerCore |
| `DashiBoard` | HTTP server (`bin/` has an example launcher) | all of the above |
| `frontend/` | SolidJS + Vite + Tailwind, `ag-grid`, `@thisbeyond/solid-select`, `@viz-js/viz` | the server, over HTTP |

## Cards: one type, described twice

A card is an annotated Julia struct. `GaussianEncodingCard`, at
`Pipelines/src/cards/gaussian_encoding.jl:87-93`:

```julia
@kwarg struct GaussianEncodingCard{M <: TemporalProcessingMethod} <: SQLCard
    method::M = IdentityMethod()
    input::String & (dashi = JSON_VARIABLE,)
    n_components::Int & (dashi = json_integer(minimum = 1),)
    lambda::Float64 = 0.5 & (dashi = json_number(exclusiveMinimum = 0),)
    suffix::String = "gaussian" & (dashi = json_string(minLength = 1),)
end
```

`composite_schema` (`Pipelines/src/structs/json_schema.jl:38-54`) walks the struct with
StructUtils' `fieldtags`/`fielddefaults` and emits JSON Schema: Julia field types map to
JSON types, the `dashi` tag merges in as constraints, and a field is `required` when it has
no default and is not nullable. `card_schema` (`Pipelines/src/structs/card_schema.jl:38-57`)
wraps that per registered card type.

The same fields are then described a **second** time for the UI. Each card hand-writes a
`CardWidget` constructor (`gaussian_encoding.jl:152` onwards) plus a TOML file
(`Pipelines/assets/config/gaussian_encoding.toml`). The `Widget` struct
(`Pipelines/src/widgets.jl:3-17`) carries `widget` (`"input"` or `"select"`), `key`,
`label`, `placeholder`, `value`, `min`, `max`, `step`, `options`, `multiple`, `type`,
`visible` and `required`. `card_widgets()` assembles them; the server returns them as JSON
from `get_card_widgets` (`DashiBoard/src/handlers.jl:14-17`).

Three things exist only in that second description and have no JSON Schema equivalent:

- **Conditional visibility.** `visible = {method: ["identity"]}` means "render this field
  only when the sibling field `method` holds one of these values". `required` has the same
  shape and defaults to `visible`. Evaluated client-side in
  `frontend/src/cards/card.jsx:33-40`.
- **Method-dependent sub-widgets.** `method_dependent_widgets`
  (`Pipelines/src/widgets.jl:64-81`) emits widgets with dotted keys such as
  `method_options.dayofyear.max`, one per variant of a tagged union.
- **Dynamic enums.** Some selects list the column names available at that point in the
  pipeline. The frontend computes them from the other cards' declared outputs
  (`frontend/src/cards/card.jsx:8-27`), using an `OutputSpec(field, suffixField,
  numberField)` the backend sends per card.

Cards nest. `ClusterCard{M <: ClusteringMethod}` has a `method` field; `KMeansMethod{D <:
DissimilarityMethod}` has a `dissimilarity` field; `WeightedMinkowskiMethod` has `weights`
and `p`. Three levels. The type bound narrows the options: `KMeansMethod` admits all nine
dissimilarities, `DBSCANMethod{D <: MetricMethod}` only the six true metrics
(`cluster.jl:20`, `cluster.jl:43`).

Some constraints span levels. `WeightedSqEuclideanMethod.weights` must match the card's
`inputs` in length and order — a leaf constrained by a field two levels above it.

## The pipeline document

Nodes and groups, in TOML or JSON. `Pipelines/test/static/configs/groups.toml`:

```toml
[[nodes]]
id = "pca"
[nodes.card]
type = "dimensionality_reduction"
method = {type = "pca"}
n_components = 2
inputs = [
    {nodes = ["log"]},
    {groups = ["weather"], through = ["rescale"]}
]

[groups]
weather = {cols = ["PRES", "TEMP"]}
```

- **Edges are inferred, never declared.** A node names the *variables* it consumes and
  produces; the DAG is derived from that (`Pipelines/src/dag.jl:30-56`). There is no edge
  object in the document and no user-drawn connection.
- **A dependency item carries exactly one selector** — `cols`, `nodes` or `groups`
  (`group_api/deps.jl:41`) — optionally qualified by `through`. `cols` means literal source
  columns; `nodes` means *every* output column of those nodes (`deps.jl:107`); `groups`
  means the resolved columns of other groups. `through` is a **renaming**, not a filter:
  `pass_through` appends those nodes' suffixes to each name (`deps.jl:98-102`), so
  `{groups = ["weather"], through = ["rescale"]}` resolves to the rescaled weather columns.
- **A dependency is one item or a list**, and a list is a union — `Context` appends
  (`deps.jl:113-120`).
- **A group is written in that same vocabulary.** `group_schema() = copy(JSON_VARIABLES)`
  (`group_api/schema.jl:50`), so a group may reference nodes and other groups, not only raw
  columns. The enum-bearing context object is `VariableConfig` (`schema.jl:3-7`).
- **The rendered graph is bipartite.** `Pipelines.graphviz` (`dag.jl:87-126`) emits DOT with
  vertices for *both* cards and variables, edges card→variable and variable→card.
- **Validation** is `validate_pipeline_schema` (`group_api/schema.jl:71-99`): a
  `JSONSchema.Schema` per card type and per group, throwing
  `SchemaValidationError(culprit, issue)`.
- Nodes carry `update`, `train` and `invert` flags and a serialised `state`
  (`Pipelines/src/node.jl:7-28`).

## The current frontend

Left tabs **Load / Filter / Process**, right tabs **Spreadsheet / Visualization / Graph**
(`frontend/src/App.jsx:88-98`). Submit posts `{filters, cards}` to `evaluate-pipeline`
(`App.jsx:49-52`). Filters are a separate concept from cards: `handlers.jl:22-27` builds
`Filter.(spec["filters"])` and calls `DataIngestion.select` to materialise a `selection`
table *before* the pipeline runs. Filter widgets are data-derived — the interval filter's
bounds come from the column's own min/max (`frontend/src/filters/interval-filter.jsx:22-23`).

## The DashiBoard server

`DashiBoard/src/launch.jl` registers six routes on port 8080 by default:

| Route | Purpose |
|---|---|
| `POST /get-acceptable-paths` | browse the data directory |
| `POST /load-files` | ingest files into the repository |
| `POST /get-card-widgets` | the widget JSON described above |
| `POST /evaluate-pipeline` | run filters + cards; returns summaries, visualisation, report and Graphviz DOT |
| `POST /fetch-data` | paged rows for the spreadsheet |
| `GET /get-processed-data` | download |

It has no schema endpoint, no validation endpoint and no persistence.

## Constraints on the refactor

- DashiBoard's backend is and stays Julia. It is not being ported.
- The standalone UI must not depend on nexus-weaver-pro being present or running.
