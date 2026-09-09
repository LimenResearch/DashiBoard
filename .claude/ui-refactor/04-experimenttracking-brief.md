# 15 — ExperimentTracking.jl reconnaissance brief

Author: the ExperimentTracking session. Owns this file only.

Line numbers are against ExperimentTracking `main` at `9e0ac99` (`rename JSONResponse to
JSONSuccess`), which is the base of branch `ds-DashiUI`. Reconnaissance was read-only; nothing
in this repository was modified.

Citations are `ExperimentTracking:path:LINE`. Where I cite Pipelines, DataIngestion,
DuckDBUtils or the DashiBoard server I use `DashiBoard:<Package>/src/...` — but see
[§0.3](#03-the-pipelines-you-read-is-not-the-pipelines-i-build-against) first, because the
Pipelines in the DashiBoard working tree is **not** the Pipelines this package resolves.

Everything marked **VERIFIED** was executed, not merely read. The scripts are in the session
scratchpad; each is reproducible with `julia --project=test`.

---

## 0. Read this before the rest — three corrections to the shared documents

`01-decisions.md` is binding, and I am not working around it quietly. But three of its load-bearing
premises about *this* repository are false, and one of them is false in a way that changes the
answer to §12's own open questions. Stating them up front because §§1–9 below all depend on them.

### 0.1 `02-stack.md` describes a branch, not `main`

`02-stack.md` says ExperimentTracking's `api/v1` has **five** methods including

> | `validate` | `{valid, source_vars, output_vars}`, from the same parse `train`/`evaluate` use (`handlers.jl:83-90`) |

and that "Progress is opt-in: passing `run_id` wraps the callbacks and emits events."

**Neither exists on `main`.** `main` serves exactly four methods —
`train`, `evaluate`, `cards`, `schema` (`ExperimentTracking:src/api/handlers.jl:5-10`) — and
contains no `run_id`, no event vocabulary and no `parse_execute_params`.

VERIFIED by asking the running server:

```
### methods served on main: ["cards", "evaluate", "schema", "train"]
unknown method 'validate'  => {"version":"2.0.0","id":6,
    "error":{"code":-32601,"message":"*Method not found*\nMethod validate not found"}}
```

The described code is real, but it lives on the unmerged branch `ds/file-mode-and-run-events`.
The cited line numbers match that branch exactly: `validate_handler` is at lines 83-90 of
`ds/file-mode-and-run-events:src/api/handlers.jl`, and `schema_handler` at 138-145 — the two
citations `02-stack.md` and §12 of `01-decisions.md` use. The lead session read a working tree
that had that branch checked out.

The branch diverged at `7b27527` and is **three commits ahead / six commits behind**:

```
main..ds/file-mode-and-run-events   c905e87 validate returns the pipeline's column dependencies
                                    07b270a Add a `validate` wire method
                                    3fcdd8a File mode over JSONRPC, per-run progress events
ds/file-mode-and-run-events..main   9e0ac99 rename JSONResponse to JSONSuccess
                                    af45b18 use source_metadata to specify table cols (#22)
                                    139fec9 update DataFlow docs
                                    6384971 simplify execute handler
                                    82374b7 Implement probing API (#21)
                                    893fcb3 Better support for file based API (#19)
```

They are not merely divergent, they **solve the same problem differently**. `main` answered
"validate without executing" with a *route*, not a method: every handler is split into a
validation phase that returns a thunk, and `api/v1/probe` runs the validation and discards the
thunk (`ExperimentTracking:src/api/handlers.jl:13-14`,
`ExperimentTracking:src/api/json_rpc.jl:159-160`, `ExperimentTracking:src/api/router.jl:25-29`).
That is a *better* mechanism than the branch's `validate` method — it applies to every method
present and future, with no second validator to drift — but it returns `null`, not
`{valid, source_vars, output_vars}`.

**This is the single most consequential fact in this brief**, because `01-decisions.md` §2 says:

> That is the same dependency analysis ExperimentTracking's `validate` returns as `source_vars`,
> so the UI produces it by calling `validate` before saving.

On `main` there is nothing to call. See [§4.4](#44-what-validate-must-become) — the fix is small
and I recommend it, but it is *work*, not an existing capability.

### 0.2 AgentGraph is already broken against `main`

`agentgraph:src/agentgraph/tools/remote_procedure.py:407-412` posts `{"method": "validate", ...}`.
Against `main` that is a `-32601`. Two more live incompatibilities, both VERIFIED:

- **`load_options` is silently dropped.** AgentGraph sends it as a top-level param
  (`agentgraph:src/agentgraph/tools/remote_procedure.py:258-262`). `main` renamed that field to
  `source_options` and moved it *inside* `DataFlow` (`ExperimentTracking:src/entries.jl:119`,
  consumed at `ExperimentTracking:src/interface.jl:49`). `make` ignores unknown keys, so no error
  is raised:
  ```
  parsed DataFlow.source_options = Dict{String, Any}()   (load_options was Dict("nullstr" => "NA"))
  ```
  A caller passing `nullstr`, `delim` or `types` gets them ignored and a silently mis-parsed table.
- **`run_id` is silently dropped** (`remote_procedure.py:264-268`). Harmless today, but it means
  the correlation id AgentGraph records is not recorded anywhere.

Whoever owns the merge decision should know these are live, not hypothetical.

### 0.3 The Pipelines you read is not the Pipelines I build against

`ExperimentTracking:Project.toml:23-27` pins Pipelines to the **git URL**
`https://github.com/LimenResearch/DashiBoard`, not to `../Pipelines`. It resolves to
`~/.julia/packages/Pipelines/ruNcy`, which **differs from
`/home/dariosarra/Documents/Limen/DashiBoard/Pipelines`** in `src/dag.jl`,
`src/group_api/dag.jl`, `src/group_api/deps.jl`, `src/pipeline.jl`, `src/utils.jl`,
`src/Pipelines.jl` and `src/cards/streamliner.jl`.

The differences are refactorings of one design, not behaviour changes — `deps.jl`'s
`DepsParser`/`Context` in the checkout is a rewrite of the resolved copy's
`Configuration`/`parse_deps!`. Every claim in this brief holds in **both**. But the DashiBoard
session should know that `Pipelines/src/group_api/deps.jl:98` (`pass_through`, `01-decisions.md`
§12) is a checkout-only line number, and that shipping a Pipelines change requires a git push
before ExperimentTracking sees it. **Recommendation, cheap and immediate:** add
`Pipelines = {path = "../DashiBoard/Pipelines"}` to a dev manifest for the duration of this
refactor, or all four repositories will be integrating against stale copies of each other.

---

## 1. Config, DataFlow and the registry

### 1.1 The five structs

There is no hand-written serialisation anywhere. Every struct is `StructUtils.@kwarg`, built from
a dict by `make`, and flattened to SQL parameters by one generic `to_params`.

**`Run`** — `ExperimentTracking:src/entries.jl:18-24`

| field | type | source |
|---|---|---|
| `_id` | `Int64` = `0` | `nextval` on the registry sequence, stamped by `set_id` (`entries.jl:26`, `queries.jl:53-57`) |
| `time` | `DateTime` = `now()` | construction time |
| `from` | `Union{Int64,Nothing}` | the `_id` of the run whose weights were loaded |
| `trained` | `Bool` | `train`/`evaluate` |
| `directory` | `Union{String,Nothing}` | where `.jld2` node weights went |

`_id == 0` means "not yet inserted"; `insert_entry` rejects it (`queries.jl:42`).

**`Config`** — `ExperimentTracking:src/entries.jl:75-79`. **This is the document.**

```julia
@kwarg struct Config
    filters::Vector{StringDict} = StringDict[]
    nodes::Vector{StringDict}   = StringDict[]
    groups::StringDict          = StringDict()
end
```

`StringDict = Dict{String,Any}` (`utils.jl:3`). All three fields are **untyped JSON bags**: `Config`
does no parsing and imposes no schema of its own. `Card`, `Node` and `Filter` are constructed later,
from these dicts, by `initialize_filters` / `initialize_pipeline`.

**`DataFlow`** — `ExperimentTracking:src/entries.jl:112-124`. Nine fields, four of them added since
`02-stack.md` was written:

```julia
@kwarg struct DataFlow
    id_var::String                              # required
    source::String                              # required
    destination::String                         # required
    schema::Maybe{String}   = nothing
    database::Maybe{String} = nothing
    file_based::Bool        = false             # NEW since 02-stack
    source_options::StringDict      = StringDict()   # NEW — reader kwargs
    destination_options::StringDict = StringDict()   # NEW — rejected if non-empty
    source_metadata::StringDict     = StringDict()   # NEW — ["cols"] drives validation
end
```

**`Result`** — `ExperimentTracking:src/entries.jl:143-145`: `reports::Vector{StringDict}`, one per
node, positional, from `Pipelines.report` (`interface.jl:100`). Marked
`# TODO potentially enrich Result`. Note the *positional* correlation: nothing in a report says
which node produced it. A UI wanting per-node results must zip against `config.nodes` by index.

**`Entry`** — `ExperimentTracking:src/entries.jl:167-172`: `Run`, `Config`, `DataFlow`, `Result`.
One registry row.

### 1.2 Serialisation — one path, both directions

The registry table is flat: `ENTRY_COLUMNS = [RUN; CONFIG; DATA_FLOW; RESULT]`
(`ExperimentTracking:src/schema.jl:52`), the four struct field lists concatenated
(`schema.jl:22-50`). There is no nesting and no foreign key; `Entry` is a *view* over one row.

Write path: `to_params(e::Entry)` → `to_params` per struct → `make(SymbolDict, x)` then
`to_params!` maps `to_param` over the values (`entries.jl:149-150,176`; `utils.jl:13-19`).
`to_param` sends `AbstractVector`/`AbstractDict` through `to_json` (**`sort_keys = true`**,
`utils.jl:7-9`) and `nothing`/`missing` to `missing`. `insert_entry` wraps each JSON column in
`json($col)` (`queries.jl:36-39,41-51`).

Read path: `row2entry` slices the row by the same four column lists and `make`s each struct back
(`entries.jl:178-184`); `row2dict` parses JSON columns and maps SQL `missing` to `nothing`
(`utils.jl:21-28`).

**`sort_keys = true` is load-bearing, not cosmetic.** `get_entries` matches with
`Get(col) IS NOT DISTINCT FROM json($col)` (`queries.jl:59-63,72-76`), i.e. **JSON equality on the
serialised text**. Canonical key order is what makes "have I run this config before?" answerable
at all. Any UI that saves a `Config` must round-trip it through this same serialiser, or two
identical pipelines will not match. **This is the closest thing the project has to a content
address for a pipeline, and the UI should use it** — see §7.4, capability 4.

### 1.3 Parsing a config TOML

`TOML.parsefile(path)` → `Dict{String,Any}` → `Config(d) = make(Config, d)`
(`ExperimentTracking:src/entries.jl:81`; exercised at `test/structs.jl:3-4`). That is the whole
pipeline. TOML and JSON are interchangeable because both land as `Dict{String,Any}` first —
`test/static/configs/config.toml` and `test/static/configs/http.json` are the same document in two
syntaxes.

`make` **ignores unknown keys and does not validate**. A misspelled `nodes` key yields an empty
pipeline, silently. All real validation happens later, in `initialize_pipeline` →
`Pipeline(nodes, groups, cols)` → `validate_pipeline_schema`
(`DashiBoard:Pipelines/src/group_api/dag.jl:18`).

### 1.4 Confirming the two claims in the question

**"`Config` is exactly what the UI should emit"** — confirmed, with two caveats worth acting on.

Confirmed: `Config` is `{filters, nodes, groups}` and nothing else (`entries.jl:75-79`); it matches
AgentGraph's `ConfigInput(fields=("nodes","groups","filters"))`
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:150-161`) key for key; it is
`Config(d)`-constructible from any dict; and it is what the registry stores and returns.

Caveat 1 — **the wire is flat, so `Config` and `DataFlow` are not actually separated in transit.**
`execute_handler` builds *both* from the same dict:

```julia
user_flow = DataFlow(d)     # ExperimentTracking:src/api/handlers.jl:19
config    = Config(d)       # ExperimentTracking:src/api/handlers.jl:21
```

`d` is the params object itself, so `train` params are `{id_var, source, destination, schema,
database, file_based, source_options, destination_options, source_metadata, filters, nodes,
groups, from}` all at one level. AgentGraph flattens its nested `dataflow` object precisely to
match (`agentgraph:src/agentgraph/tools/remote_procedure.py:356-358`: *"DataFlow fields sit FLAT
beside the pipeline fields in params"*). The separation is by *field name*, not by structure.
Consequence: a saved `Config` document that happens to carry a `source` key would have it absorbed
into `DataFlow` on the next run, and the UI would never be told. Cheap guard, recommended:
`additionalProperties` checking on the saved document, or a `Config`-only import path that strips
non-`{filters,nodes,groups}` keys.

Caveat 2 — **there is no version field.** `Config` has no `version`, `dialect` or `type` key. The
document the UI is about to start writing, saving, importing and round-tripping through two
registries has no way to say which vocabulary it is written in — which matters a great deal given
[§4](#4-the-schema-dialect-gap), where two mutually-exclusive dialects for exactly these documents
are both live in the codebase right now. **Recommendation: add an optional `version` key to
`Config` before the UI ships**, not after. It is one field, one `CONFIG_COLUMNS` entry, and it is
the difference between "old configs are detectable" and "old configs fail with a schema error
nobody can attribute".

**"`Config` carries no DataFlow"** — confirmed, unambiguously. `Config` and `DataFlow` are
disjoint structs (`entries.jl:75-79` vs `112-124`), stored in disjoint column groups
(`schema.jl:30-34` vs `36-46`), and `Entry` is what joins them (`entries.jl:167-172`). The same
`Config` runs against any `DataFlow`; `test/interface.jl:37,103` does exactly that, running one
config against a table flow and a file flow. §2 of `01-decisions.md` is correct here.

---

## 2. Serving the UI

### 2.1 What it takes: about 40 lines

Today `get_router` builds a bare `HTTP.Router()` and registers two POST routes
(`ExperimentTracking:src/api/router.jl:19-31`). Adding static assets needs four things, all
supported by HTTP.jl 2.6.4 as resolved.

**A static route and an SPA fallback — one mechanism, not two.** HTTP.jl's router supports a
trailing double wildcard: *"`/api/**`: double wildcard matches any number of trailing segments in
the request path; the double wildcard must be the last segment"*
(`HTTP/4AUPl/src/Handlers.jl:373`, registered at `Handlers.jl:219-225`). So one
`HTTP.register!(router, "GET", "/**", asset_handler)` covers both: the handler maps the path to a
file under the build directory, serves it if it exists, and otherwise returns `index.html` with
200 — which *is* the client-side-routing fallback.

**Precedence is already correct, no ordering care needed.** `match` tries exact segments first,
then conditional, then single wildcard, then doublestar (`HTTP/4AUPl/src/Handlers.jl:275-315`). So
`POST api/v1` wins over `GET /**` structurally, regardless of registration order. One wrinkle worth
knowing: a `GET /api/v1` matches the exact node, finds no GET method, yields `missing`, and then
**falls through to the doublestar** (`Handlers.jl:280-281,308`) — so a GET to the API path serves
`index.html` rather than a 405. Harmless, mildly confusing when debugging.

**MIME types must be hand-rolled.** HTTP.jl ships `HTTP.sniff` (`src/sniff.jl:48-59`) but it is
content-based and will not reliably distinguish `.css` from `.js` from `.svg`. A ~10-line
extension→MIME table is required. This is the only genuinely fiddly part and it is not very fiddly.

**Cache headers.** Vite emits `index.html` plus content-hashed `assets/*.js|css`. The correct and
entirely standard split:

- hashed assets under `/assets/` → `Cache-Control: public, max-age=31536000, immutable`
- `index.html` → `Cache-Control: no-cache` (revalidate every load)

Getting this backwards is the classic failure where users get a stale bundle after a deploy. It is
two `if`s.

**Build-output location.** The frontend has no `build.outDir` override
(`DashiBoard:frontend/vite.config.mjs:10-12`), so Vite's default `frontend/dist/` applies. Julia
cannot read a sibling repository's directory at runtime, so the path must be a parameter:
`get_router(registry, repository; directory, assets::Union{AbstractString,Nothing} = nothing)`,
with static routes registered only when `assets !== nothing`. That keeps the API-only deployment
(what AgentGraph uses) unchanged and un-broken.

Sketch, to be concrete about the size of the thing:

```julia
const MIME_TYPES = Dict(".html" => "text/html", ".js" => "text/javascript",
    ".css" => "text/css", ".svg" => "image/svg+xml", ".json" => "application/json",
    ".woff2" => "font/woff2", ".png" => "image/png", ".ico" => "image/x-icon")

struct AssetHandler
    root::String
end

function (h::AssetHandler)(req::HTTP.Request)
    rel = lstrip(HTTP.URI(req.target).path, '/')
    path = normpath(joinpath(h.root, rel))
    # containment check: normpath collapses `..` before we test
    startswith(path, h.root) || return HTTP.Response(403)
    if isfile(path)
        cache = startswith(rel, "assets/") ?
            "public, max-age=31536000, immutable" : "no-cache"
        return HTTP.Response(200, [
            "Content-Type" => get(MIME_TYPES, last(splitext(path)), "application/octet-stream"),
            "Cache-Control" => cache,
        ], body = read(path))
    end
    return HTTP.Response(200, ["Content-Type" => "text/html", "Cache-Control" => "no-cache"],
        body = read(joinpath(h.root, "index.html")))
end
```

The `startswith` containment check is not optional. `normpath` collapses `..` before the test, so
that ordering matters; without it, `GET /../../etc/passwd` reads outside the build directory.

### 2.2 Is it a bad idea?

**No, and it is materially better than the alternative** — but for a reason `01-decisions.md` §10
does not state, which is worth adding to the record.

§10 argues same-origin on the grounds of "no cross-origin permission headers, no separate auth
plumbing, one process and one port". All true. The stronger argument is that **the alternative is
already implemented in this project and is a known liability**: the DashiBoard server's answer to
cross-origin is `Access-Control-Allow-Origin: *` on every response, unconditionally, with
`Access-Control-Allow-Headers: *` and no origin allow-list
(`DashiBoard:DashiBoard/src/middleware.jl:1-11`). That is acceptable for `localhost` development
and unacceptable for anything else, and it is the thing same-origin serving deletes rather than
configures.

Three real objections, none disqualifying:

1. **It couples a Julia release to a JS build artifact.** Something must build `frontend/dist` and
   put it where Julia can find it. Making `assets` a runtime parameter (above) rather than an
   `Artifacts.toml` dependency keeps this loose: dev points at `frontend/dist`, production points
   at a packaged directory, and neither requires re-resolving the Julia environment.
2. **`read(path)` loads whole files into memory.** Fine for a bundle (hundreds of KB). If the same
   mechanism is later reused for data downloads it must become streaming — `stream_data`
   (`DashiBoard:DashiBoard/src/middleware.jl:40-58`) is the existing pattern and it works, but
   note it is a `Stream` handler while `JSONHandler` is a `Request` handler. `HTTP.Router` supports
   both (`Handlers.jl:408,426`), so they can coexist in one router; they just look different.
3. **Same-origin does not, by itself, make the app safe to expose.** There is no authentication
   anywhere in this package. Same-origin removes the CORS question; it does not answer "who may
   POST `train`". Out of scope for the refactor, but it should be *said* rather than assumed
   solved, because "one process, one port, no cross-origin headers" reads like a security posture
   and is not one.

On §11's runtime-configurable API base: the current frontend fails this today.
`DashiBoard:frontend/src/requests.js:1` does `import { host, port } from "./request.json"` and
`getURL` builds `"http://" + host + ":" + port + "/" + page` (`requests.js:23-25`) — a build-time
constant baked into the bundle, exactly what §11 forbids. Served same-origin the fix is also the
simplest possible one: **relative URLs**, with an optional runtime override read from a
`<meta>` tag or a small non-hashed `config.json` fetched at boot. That satisfies §11's "one bundle,
two deployments" without any build-time branching.

---

## 3. The five orphaned capabilities

### 3.1 The dependency situation, which decides most of this

The five capabilities are not equally orphaned. Four of the five are implemented in packages
**ExperimentTracking already depends on**:

| Capability | Where the logic actually lives | New dep for ExperimentTracking? |
|---|---|---|
| `get-acceptable-paths` | `DataIngestion.acceptable_paths` (`DashiBoard:DataIngestion/src/load.jl:37-43`) | **no** |
| `load-files` | `DataIngestion.load_files` (`DashiBoard:DataIngestion/src/load.jl:58-64,90-99`) | **no** |
| `fetch-data` | `DuckDBUtils.export_table`, `to_nrow`, `colnames` (`DashiBoard:DuckDBUtils/src/table.jl:51,105`) | **no** |
| `get-processed-data` | `DuckDBUtils.export_table` | **no** |
| Graphviz DOT | `Pipelines.graphviz` (`DashiBoard:Pipelines/src/dag.jl:87-122`) | **no** — but see §3.3, it does not work |

`ExperimentTracking:Project.toml:8,11,17` already lists DataIngestion, DuckDBUtils and Pipelines.
The DashiBoard server's handlers are **thin HTTP wrappers over library functions**, not the
implementations. `get_acceptable_paths` is three lines
(`DashiBoard:DashiBoard/src/handlers.jl:1-5`); `load_files` is five (`handlers.jl:7-12`);
`get_processed_data` is seven (`handlers.jl:78-85`). Moving them is re-wrapping, not porting.

So the cost question is not "can these move" but "what state do they need", and that is where the
real difference is.

### 3.2 The state problem — the actual obstacle

The DashiBoard server is **stateful in a way ExperimentTracking is not**, and this is the design
gap that has to be closed regardless of which package survives.

- `DashiBoard:DashiBoard/src/DashiBoard.jl:43,51-55` holds `const REPOSITORY = Ref{Repository}()`,
  a **process-global** DuckDB file in a `Scratch` directory, initialised in `__init__`.
- Table names are **hardcoded string literals**: `"source"` and `"selection"`
  (`handlers.jl:10,27,34,49,81`; `DashiBoard:DataIngestion/src/load.jl:9-12`).
- The flow is implicitly sequential and stateful: `load-files` writes `source`;
  `evaluate-pipeline` writes `selection`; `fetch-data` and `get-processed-data` read whichever of
  those two the client asks for. **One user, one dataset, one process.**

ExperimentTracking is the opposite: `Repository` is a parameter threaded from `get_router`
(`ExperimentTracking:src/api/router.jl:19-24`), table names come from the request's `DataFlow`,
and temporary tables are scoped per call via `with_table_name`
(`ExperimentTracking:src/interface.jl:48,70-71`). A request carries its own world.

**This is the thing to cost, not the line count.** `fetch-data` and `get-processed-data` are not
"paged rows" and "download" in the abstract; they are "paged rows *of the global `selection`
table*". In ExperimentTracking there is no `selection` table — it is a `with_table_name` temporary
that is dropped when `_execute` returns (`interface.jl:70-96`). The destination is written to
`flow.destination` and that is all that survives.

So moving them means **deciding what they read**, and there are exactly two coherent answers:

- **(a) Read the run's destination.** `fetch-data` takes a `run_id`, looks up the `Entry`
  (`get_entry_by_id`, `ExperimentTracking:src/queries.jl:84-93`), and pages over
  `entry.flow.destination`. Honest, stateless, matches the registry model, and gives the UI
  something DashiBoard cannot: *previous* runs are browsable too. Cost: the destination must be
  addressable, which it is (a table name or a file path).
- **(b) Read an arbitrary table/path named in the request.** Simpler, one method, no registry
  lookup — but it is an unauthenticated "read any table in my database" endpoint, and worse,
  in file mode an arbitrary-file-read. Would need a containment check like §2.1's.

**I recommend (a)** and note it is strictly more useful than what DashiBoard does today.

Costs, concretely:

| Capability | Cost | Notes |
|---|---|---|
| `get-acceptable-paths` | **~15 lines.** Trivial. | `acceptable_paths()` reads the `DataIngestion.DATA_DIR` ScopedValue (`load.jl:38`). ExperimentTracking never sets it. Needs a `data_directory` parameter on `get_router`, set with `@with` at serve time — the same pattern `DashiBoard:DashiBoard/src/launch.jl:25-30` already uses. Directory-traversal containment is `acceptable_paths`' own concern and it is already relative-path-only. |
| `load-files` | **~30 lines, plus a decision.** | The function is ready. The question is *where the loaded table goes*. In DashiBoard it goes to the global `"source"`. In ExperimentTracking there is no global anything. Cleanest: `load-files` takes a target table name and a `Repository`, i.e. it becomes an explicit ingest into a named table, and "Connect source" then names that table in the `DataFlow`. |
| `fetch-data` | **~60 lines.** The largest of the five. | Paging, sort model, and the JSON envelope `{"values": [...], "length": n}` (`DashiBoard:DashiBoard/src/handlers.jl:70-73`). Note it is a **`Stream` handler** that streams from a temp file rather than materialising — worth preserving; a naive `Response(body=...)` version will hold a page in memory, which is fine, but the streaming version already exists and is only slightly longer. Plus the §3.2 decision. |
| `get-processed-data` | **~20 lines**, given the §3.2 decision. | `export_table` + `stream_data`. |
| Graphviz DOT | **See §3.3 — this one is not a move, it is a fix.** | |

### 3.3 Graphviz: the capability does not currently work for ExperimentTracking's pipelines

This is a finding, not a cost estimate. **VERIFIED:**

```
### 1. Pipeline type from group API
enriched_digraph type = Pipelines.GroupDiGraph{Int64}

### 2. graphviz on a group-API pipeline
THREW: MethodError
MethodError: no method matching graphviz(::IOBuffer, ::Pipelines.GroupDiGraph{Int64},
                                         ::Vector{Pipelines.Node})
```

`Pipelines.graphviz` has exactly one method, on `EnrichedDiGraph`
(`DashiBoard:Pipelines/src/dag.jl:87`), reached through
`graphviz(io, p::Pipeline) = graphviz(io, p.enriched_digraph, p.nodes)`
(`DashiBoard:Pipelines/src/pipeline.jl:35`). But the group API returns a `GroupDiGraph`
(`DashiBoard:Pipelines/src/group_api/dag.jl:1-6,24`), and `initialize_pipeline` always uses the
group API (`ExperimentTracking:src/entries.jl:131-134`).

The reason DashiBoard's server does not hit this is that **it never uses the group API at all**:
`evaluate_pipeline` does `Card.(spec["cards"])` then `Pipelines.Node.(cards)`
(`DashiBoard:DashiBoard/src/handlers.jl:23-24`), the flat pre-groups constructor, which yields an
`EnrichedDiGraph` (`DashiBoard:Pipelines/src/pipeline.jl:26-30`). **The DashiBoard server has not
been migrated to the group API.** That is a much bigger fact about the DashiBoard package than the
graphviz method itself, and it bears directly on §3.4.

So "move Graphviz DOT rendering here" is mis-stated. The work is:

1. **Write `graphviz(io, ::GroupDiGraph, nodes)` in Pipelines.** This is required whoever hosts the
   endpoint, and `01-decisions.md` §5 already asks for it ("needs updating from its current
   bipartite card-and-variable form to the node + group vocabulary"). Groups are already carried:
   `GroupDiGraph` has a `groups::Vector{Vector{String}}` field (`group_api/dag.jl:5`) holding each
   group's resolved columns, and the graph's vertices are already `[nodes; groups]` in that order
   (`group_api/deps.jl:73-76,85`). The information is there; only the rendering is missing.
2. **Then expose it**, which is a two-line handler wherever it lives.

Estimate: the DOT writer is ~40 lines mirroring `dag.jl:87-122`, plus a decision about whether
group vertices render as a third shape or as clusters. The endpoint is trivial. **Recommend doing
this in Pipelines regardless of the §3.4 outcome** — a `Pipeline` that cannot render itself is a
gap in Pipelines, not in either server.

### 3.4 Should the `DashiBoard` package survive as a server?

**Recommendation: no. Retire it as a server, in one step, once the five capabilities land here.**
Here is the argument and then the case against.

**For retiring it.**

1. **Its API is superseded in substance, not just in the one method `02-stack.md` credits.**
   `02-stack.md` says "Only `get-card-widgets` is genuinely superseded." That understates it.
   `evaluate-pipeline` is *also* superseded — by `train`/`evaluate`, which do strictly more
   (registry persistence, `from` lineage, weight save/load, file mode, external databases) — and
   `01-decisions.md` §7 already retires the `{filters, cards}` request shape that
   `evaluate-pipeline` exists to serve. So two of six are superseded and three of the remaining
   four are 3–7-line wrappers over libraries ExperimentTracking already depends on.
2. **It is on the wrong side of the group-API migration.** Per §3.3, `evaluate_pipeline` still
   builds flat `Card`/`Node` lists. `01-decisions.md` §6 requires the group vocabulary throughout.
   Keeping the DashiBoard server means *migrating* it to the group API — real work, on code whose
   only consumer is the frontend that §7 deletes. That is the strongest single argument: the
   effort to keep it is not zero, and it buys nothing the refactor wants.
3. **Its statefulness is incompatible with the target.** §3.2. A global `Ref{Repository}` and
   hardcoded `"source"`/`"selection"` cannot serve a UI that binds source per invocation
   (`01-decisions.md` §2), and cannot serve two users.
4. **It carries a heavy dependency the API does not need.** `DashiBoard` imports
   `AlgebraOfGraphics` and `CairoMakie` (`DashiBoard:DashiBoard/src/DashiBoard.jl:39`) solely to
   load the PipelinesMakie extension for `Pipelines.visualize`. That is the single largest
   contributor to its load time, and ExperimentTracking is free of it. Folding DashiBoard's
   *endpoints* into ExperimentTracking is cheap; folding its *dependency closure* in is not, and
   would be a real regression for AgentGraph, which wants a fast-starting RPC server.
5. **Two servers both defaulting to port 8080 is an active hazard.** `02-stack.md` notes it;
   `DashiBoard:DashiBoard/src/launch.jl:5` and `ExperimentTracking:test/api.jl:16` confirm it. One
   server removes a whole class of "why is my request 404ing" confusion.

**The case against — three real points.**

1. **Visualization is a sixth capability, and it is not on the list.** `evaluate-pipeline` returns
   `visualization`: per-node CairoMakie SVGs via `Pipelines.visualize` and
   `stringify_visualization` (`DashiBoard:DashiBoard/src/handlers.jl:31-32`,
   `middleware.jl:24-25`). `01-decisions.md` §7 says the Visualization pane is "rebuilt rather than
   ported" but does not say *from what*. If it is rebuilt on server-rendered SVG, then retiring
   DashiBoard means ExperimentTracking inherits AlgebraOfGraphics and CairoMakie — objection 4
   above turns around and bites. **This is a genuine open question and I flag it as one:** either
   the new Visualization pane renders client-side from data (in which case retire freely), or it
   needs server-side Makie (in which case the plotting stack should live in a *third* thing — an
   optional package extension, or a separate render service — not in the RPC server AgentGraph
   depends on). I recommend the former and note the decision is not mine.
2. **`DashiBoard` is version `2.0.0` and named after the product.** Retiring the *server* while a
   package called `DashiBoard` is what the whole system is named is a naming mess. Mitigation:
   keep the package, empty the server. It can remain a thin meta-package that re-exports the
   others and holds the `launch` convenience entry point, now delegating to
   `ExperimentTracking.get_router`. Costs nothing, avoids the rename.
3. **It is the only thing that currently works end-to-end with a browser.** Retiring it before the
   new UI exists leaves a period with no working GUI. Sequencing, not architecture: keep it alive
   and untouched on `main` until the new UI is serving, then delete in one commit. Do **not**
   migrate it to the group API in the meantime — that is the wasted work in objection 2.

**Net:** retire the server, keep the package name as a shim, and treat the visualization question
as a real fork in the road that needs a decision before the retirement commit.

---

## 4. The schema dialect gap

### 4.1 Confirmed, and worse than described

`01-decisions.md` §12 states the gap correctly. It is confirmed, and the situation is sharper than
"cannot express `{nodes|groups|cols, through}`": **the two dialects are mutually exclusive**, and
the server is currently serving one while validating with the other.

`schema_handler` reads `vars::Vector{String}` and calls `Pipelines.card_schema(k, vars)`
(`ExperimentTracking:src/api/handlers.jl:43-48`). `card_schema(key, variable_config::Any)` is typed
`::Any` and forwards to `schema_definitions(variable_config)`
(`DashiBoard:Pipelines/src/structs/card_schema.jl:38-45`), so dispatch on the *runtime* type picks
between two methods:

| | `schema_definitions(::AbstractVector)` | `schema_definitions(::VariableConfig)` |
|---|---|---|
| defined at | `Pipelines/src/structs/card_schema.jl:27-36` | `Pipelines/src/group_api/schema.jl:28-48` |
| `$defs` keys | `variable`, `variables`, `nonempty_variables` | + `node`, `group`, `col` |
| a variable is | a bare string from an enum | an object `{nodes\|groups\|cols: [...], through?: [...]}` |
| reached by | `schema` wire method | `validate_pipeline_schema` |

VERIFIED:

```
defs keys (flat/vars)      = ["nonempty_variables", "variable", "variables"]
inputs subschema           = {"$ref":"#/$defs/variables","type":"array"}
variable def               = {"enum":["PRES","TEMP"],"type":"string"}
defs keys (VariableConfig) = ["col", "group", "node", "nonempty_variables", "variable", "variables"]
```

And the mutual exclusivity, tested against the repository's own example card
(`ExperimentTracking:test/static/configs/config.toml:29-36`) — VERIFIED:

```
### The card as written in test/static/configs/config.toml
{"group_by":{"cols":["cbwd"]},"inputs":{"groups":["weather_vars"]},"method":{"type":"zscore"},
 "partition":{"nodes":["partition"]},"type":"rescale"}

flat (what `schema` serves)            => REJECTS
      path: [partition] | instance: Dict("nodes" => ["partition"])
      | schema key: type | schema value: string
VariableConfig (what validate uses)    => ACCEPTS

### And the reverse: a flat-dialect card {"inputs": ["PRES","TEMP"]}
flat                                   => ACCEPTS
VariableConfig                         => REJECTS
```

**So the `schema` method today serves a schema that rejects every config this package can actually
run, and accepts configs it cannot run.** It is not an incomplete schema; it is the wrong one. A UI
built against `schema` as it stands would generate documents that `train` rejects at `-32602`, with
the user having no way to see why — precisely the failure mode `01-decisions.md` §3 warns about
when it says the error contract "is the only place some constraints become visible".

Nothing in the test suite catches this: `ExperimentTracking:test/api.jl:72-73` and `test/rpc.jl:33-34`
assert `schema` equals `Pipelines.card_schema(k, vars)` — i.e. they assert the server returns what
the server returns, tautologically, without ever validating a card against the result.

### 4.2 Who calls `schema` today

Exhaustively, three callers:

1. **`ExperimentTracking:test/api.jl:63` and `test/rpc.jl:23`** — the tautological tests above.
2. **`ExperimentTracking:scripts/server.jl:78-86`** — the example script, `cards = ["interp",
   "rescale"]`, `vars = ["col1","col2"]`. Not a consumer, a demo.
3. **Nothing in AgentGraph.** Confirmed: `discover()` posts `{"method": "cards"}` only
   (`agentgraph:src/agentgraph/tools/remote_procedure.py:431-445`). The prompt's note is correct.
   AgentGraph's docstring calls `discover` *"(cards + their schemas)"* but the implementation sends
   `cards` alone — a docstring/behaviour mismatch on their side, worth telling that session, and it
   means **no external consumer depends on the current `schema` shape**.

**Therefore the change is not breaking in practice.** The only callers are this repository's own
tests and its own demo script. This is as free as a wire-format change ever gets, and it argues for
fixing it properly rather than adding a parallel method.

### 4.3 What the change is

**Recommended: change the params of `schema`, keep the method name, delete the flat dialect path.**

`schema` should take what `validate_pipeline_schema` takes — the pipeline state, not a flat variable
list — so the served schema is *by construction* the schema the server validates against:

```julia
function schema_handler(d::AbstractDict)
    cards::Vector{String} = d["cards"]
    # the same three quantities validate_pipeline_schema derives (group_api/schema.jl:76-78)
    variable_config = Pipelines.VariableConfig(
        nodes  = get(d, "nodes",  nothing),
        groups = get(d, "groups", nothing),
        cols   = get(d, "cols",   nothing),
    )
    return function ()
        return StringDict(
            k => Pipelines.card_schema(k, variable_config) for k in cards
        )
    end
end
```

Three notes on this:

- **No new Pipelines method is needed.** `card_schema(key, ::Any)` already dispatches correctly
  (`card_schema.jl:38-45`) and `schema_definitions(::VariableConfig)` already exists
  (`group_api/schema.jl:28-48`). The whole change is which object ExperimentTracking constructs.
  **The group-vocabulary schema `01-decisions.md` §6 requires is already implemented and already
  in use — it just is not the one being served.** That is the good news in this section.
- **`group_schema(variable_config)` should be served too** (`group_api/schema.jl:52-56`).
  §6 requires "Add group" to use the same picker component as any card's variable field; the
  component needs the group schema, and the server has it. Add a `groups` key to the response, or a
  sibling `group_schema` method. One line either way.
- **`VariableConfig` fields are `Union{Vector{String},Nothing}` and `nothing` means unconstrained,
  not empty** (`group_api/schema.jl:3-7`, via `json_string(enum = nothing)` and `nonnothing_dict`
  dropping nothings, `structs/json_schema.jl:29-31,77-84`). So omitting `cols` yields a schema with
  no column enum at all. VERIFIED: a card referencing a nonexistent column `"a"` passes validation
  when `source_metadata` is absent, and fails only at SQL execution. **The UI must always send
  `cols`** — which is exactly why `source_metadata["cols"]` exists (§8).

**Is it breaking?** For the wire: yes, `vars` disappears. For anyone: no (§4.2). I recommend
accepting the break rather than keeping a compatibility shim, because keeping both dialects alive
is what produced this bug. If a transition is wanted, accept `vars` for one release and emit a
deprecation in the response — but I would not.

**Cost:** ~10 lines in `schema_handler`, ~30 lines of real tests (validate a known-good group card
against the served schema, and assert a flat card is rejected — the test that does not exist
today), and updating `scripts/server.jl:81`. Half a day.

### 4.4 What `validate` must become

Separate from the dialect gap, and required by `01-decisions.md` §2. Currently there is no way to
get `source_vars` out of this package over the wire (§0.1). `api/v1/probe` returns `null`.

The quantities exist and are already computed on every run:
`Pipelines.get_source_vars(pipeline)` and `get_output_vars(pipeline)`
(`ExperimentTracking:src/interface.jl:36-37`, `DashiBoard:Pipelines/src/pipeline.jl:32-33`,
`group_api/dag.jl:8-9`). They are derived and then discarded.

**Recommended: keep the probe route, and make the probe thunk return the analysis rather than
`nothing`.** The probe middleware is `Returns(Returns(nothing)) ∘ handler`
(`ExperimentTracking:src/api/json_rpc.jl:160`) — it throws away a *result* the validation phase
could just as well produce. Changing `execute_handler` to close over the parsed pipeline and having
the probe middleware call a `probe_result` accessor keeps `main`'s better mechanism *and* delivers
§2's requirement, without reintroducing the branch's separate `validate` method with its
duplicate-validator risk.

Two semantic warnings for whoever consumes `source_vars`, both inherent to how it is derived:

- **It is the union of every `{cols = [...]}` selector, not "columns present in the source".** The
  parser accumulates `cols` selectors into an `OrderedSet` regardless of whether the name is a real
  source column (`DashiBoard:Pipelines/src/group_api/deps.jl:32,46,87`). A card that names another
  card's output via `cols` lands in `source_vars` too. Set-minded clients must subtract
  `output_vars`. (The unmerged branch's docstring says exactly this — worth preserving.)
- **`id_var` is not included.** `_execute` unions it back explicitly
  (`ExperimentTracking:src/interface.jl:36`). AgentGraph's preflight checks `id_var` separately
  (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:63`), so the two are consistent today,
  but a UI computing `required_columns` for `content_metadata` must union `id_var` itself.

**Cost:** ~25 lines plus tests. This is the single highest-value change in the brief, because
`01-decisions.md` §2 makes the whole save-annotation story depend on it.

---

## 5. Filters

### 5.1 Is §8 right? Half of it, yes. The other half is not true today.

`01-decisions.md` §8 makes two claims. Taking them in turn.

**Claim A — "keeps `filters` as a top-level key of `Config` ... costs no schema change and no
registry migration." CONFIRMED, and the reasoning is better than stated.**

`filters` is a JSON column in its own right (`ExperimentTracking:src/schema.jl:31`), part of
`CONFIG_COLUMNS` (`schema.jl:30-34`) and hence of `ENTRY_COLUMNS` (`schema.jl:52`). Leaving the
document shape alone means `ENTRY_COLUMNS` is unchanged, so `initialize_registry_table`
(`queries.jl:13-22`) emits the same `CREATE TABLE`, and existing registry rows keep parsing.

The stronger reason §8 is right: **`filters` participates in registry identity.** `get_entries`
matches every populated column with `IS NOT DISTINCT FROM json($col)`
(`queries.jl:59-63,72-76`), and `test/interface.jl:63,86` looks configs up by
`to_params(config)` — filters included. Changing the filter representation would silently
invalidate lookups of every historical entry, because the JSON text would no longer match. §8's
"no registry migration" is therefore not just convenient, it avoids a data-corruption-shaped
problem. Good decision; I would not revisit it.

**Claim B — "Their UI is derived from `DataIngestion`'s `Filter` structs under section 3, so
nothing about them is hand-written." NOT TRUE TODAY, and this is the gap §8 does not budget for.**

I have to flag this explicitly per the protocol. §8 asserts filters can ride on the section-3
mechanism as-is. They cannot, for four independent reasons.

### 5.2 Are `Filter` types annotated structs from which UI can be derived the same way cards are?

**No.** Point by point against what section 3's mechanism needs:

1. **No `StructUtils`, therefore no `@kwarg`, no `dashi` tags, no `fieldtags`/`fielddefaults`.**
   `DashiBoard:DataIngestion/Project.toml` `[deps]` lists DBInterface, DuckDBUtils, FunSQL,
   IntervalSets, IterTools, Tables — **StructUtils is absent**. `composite_schema` is built entirely
   on `fieldtags(DashiStyle(), T)` / `fielddefaults(DashiStyle(), T)`
   (`DashiBoard:Pipelines/src/structs/json_schema.jl:41-42`), so it cannot be pointed at a
   `DataIngestion` struct at all. Cards are `@kwarg struct ... & (dashi = ...,)`; filters are plain
   `struct`s (`DashiBoard:DataIngestion/src/filters.jl:36-39,68-76`).
2. **No registry equivalent of `CARD_SPECS`.** Filters dispatch through a bare
   `FILTER_TYPES = Dict("interval" => IntervalFilter, "list" => ListFilter)`
   (`filters.jl:99-102`) with no label, no spec object, no `register_card` equivalent
   (`DashiBoard:Pipelines/src/card.jl:282-312`). There is no `filters` wire method and nothing to
   build one from — a UI cannot even enumerate the available filter types today.
3. **The struct field layout does not match the wire format.** This is the deepest problem.
   `IntervalFilter` has fields `colname::String` and `interval::ClosedInterval{T}`
   (`filters.jl:36-39`), but the wire form is `{"colname", "type", "interval": {"min", "max"}}`
   (`ExperimentTracking:test/static/configs/config.toml:1-4`). Two mismatches:
   - `type` is a **discriminator that is not a field**. Cards solve this with
     `tagged_composite_schema` / `match_property` (`json_schema.jl:56-73,172-185`) and
     `card_schema` injecting `json_const(key)` (`card_schema.jl:52-53`). Filters would need the
     same treatment built for them.
   - `interval` is `{min, max}` on the wire but a `ClosedInterval` in the struct. `schema_from_type`
     maps only `Integer`/`Number`/`AbstractString`/`Symbol`/`AbstractVector`/`Enum`
     (`json_schema.jl:11-16`); `ClosedInterval` matches none, so it falls through to
     `schema = StringDict()` — an **empty, entirely unconstrained schema**. Naive derivation
     produces a schema that accepts anything.
4. **`ListFilter{T}`'s element type is data-dependent.** `ListFilter` narrows `T` from the values
   it is given (`filters.jl:78-82`), so there is no static type to derive an `items` schema from.
   The right answer is to derive it from the *column's* summary, not the struct — which is
   `summarize`'s job, below.

**So filters need roughly what cards already have, built once:** a spec registry, StructUtils
annotations (adding a StructUtils dependency to DataIngestion, or defining the schemas in Pipelines
where the machinery lives), a tagged-union schema over `FILTER_TYPES`, and a hand-written
sub-schema for the interval shape.

**Cost: I estimate 1–2 days**, most of it decisions rather than typing: where the annotations live
(DataIngestion gains StructUtils, vs. Pipelines gains a `FILTER_SPECS` table), and how the
interval's `{min,max}` object is expressed. Not large — but §8's "nothing about them is
hand-written" reads as *zero*, and zero is wrong. I recommend §8 keep its conclusion (filters stay
a top-level key, derived not hand-written) and simply carry this cost explicitly.

**The one piece that genuinely is free:** §8's requirement that "the interval filter's bounds come
from the column's own min/max ... baked into the schema server-side". `DataIngestion.summarize`
already computes exactly this — `list_extrema` → `{min, max}` for numerical columns and
`list_unique_sorted` for categorical ones
(`DashiBoard:DataIngestion/src/summary.jl:26-36,62-74`). It returns precisely the two shapes the
two filter types need. That half of §8 is a wiring exercise.

### 5.3 Is `Config.filters` read anywhere outside `run_pipeline`?

Exhaustive grep over `ExperimentTracking:src/`. `Config.filters` is read in **three** places, and
the answer to the question as asked is **yes — but not in a way that constrains the UI**:

1. **`initialize_filters(c::Config, ::DataFlow) = Filter.(c.filters)`**
   (`ExperimentTracking:src/entries.jl:129`) — the only semantic use. Called from
   `_execute` (`interface.jl:110`) and, ahead of it, from `execute_handler` during the validation
   phase (`api/handlers.jl:22`).
2. **`Base.show`** (`entries.jl:85`) — display only.
3. **The registry round-trip** — `to_params` serialises it to the `filters` column
   (`schema.jl:31`, `entries.jl:149-150`), `row2entry` reads it back (`entries.jl:180`), and
   `get_entries` matches on it (`queries.jl:73`). This is §5.1's identity point.

Note the parsed filters are threaded *around* `run_pipeline`, not through it: `_execute` passes them
to `load_filtered` in file mode (`interface.jl:50`) or `DataIngestion.select` in table mode
(`interface.jl:79-82`), and `run_pipeline` (`interface.jl:1-21`) never sees them. §8's framing —
filters subset rows *before* the pipeline, cards produce columns joined back on `_id` — is exactly
right and confirmed by this control flow.

**One gap §8 should know about.** `initialize_filters` **ignores its `DataFlow` argument** —
`entries.jl:128` carries the comment `# TODO: use DataFlow to validate filters`. So:

- filters are never schema-validated (there is no filter schema, §5.2);
- filter column names are never checked against `source_metadata["cols"]`
  (`validate_pipeline_schema` receives only nodes, groups and cols —
  `entries.jl:131-134`, `group_api/schema.jl:71-78`);
- a filter naming a nonexistent column therefore fails at SQL execution, as a `-32603` internal
  error, not a `-32602` invalid-params with a useful message.

AgentGraph compensates client-side, checking `filters[i].colname` against the source artifact's
recorded columns before any HTTP call
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:64-66`). A browser UI has no such
compensation. **Recommendation: implement that TODO as part of the filter schema work** — it is a
handful of lines once `source_metadata["cols"]` is being sent, and it is what turns a stack trace
into a form error.

---

## 6. The JSON-RPC surface in full

Everything here is `main`. See [§0.1](#01-02-stackmd-describes-a-branch-not-main) for what is on the
branch instead.

### 6.1 Routes

Two, both POST, registered in `get_router` (`ExperimentTracking:src/api/router.jl:23-30`):

| Route | Behaviour |
|---|---|
| `POST api/v1` | validate, then execute |
| `POST api/v1/probe` | validate only; result is always `null` |

Note there is **no leading slash** in the registered paths (`router.jl:28-29`); HTTP.jl splits on
`/` with `keepempty=false` (`HTTP/4AUPl/src/Handlers.jl:378`) so it matches `/api/v1` regardless.

Both are the same `JSONHandler` over different handler tables. The probe table is built by
`apply_middleware(probe_middleware, handlers)` where
`probe_middleware(handler) = Returns(Returns(nothing)) ∘ handler`
(`ExperimentTracking:src/api/json_rpc.jl:153-160`) — the handler runs, its thunk is discarded and
replaced by a no-op. This is the mechanism that makes "validate accepts" and "train would accept"
the same statement by construction, and it is the thing `main` has that the branch does not.

Responses: `200` with a JSON body, or `204 No Content` when the result is `nothing`
(`ExperimentTracking:src/api/router.jl:12-16`). **HTTP status is never used for errors** — a
`-32700` parse failure is still `200` (asserted at `ExperimentTracking:test/api.jl:45`;
AgentGraph relies on it: `remote_procedure.py:372` *"HTTP 200 even for errors — never check
status"*).

### 6.2 The four methods

Registered in `get_handlers` (`ExperimentTracking:src/api/handlers.jl:1-11`). VERIFIED:
`["cards", "evaluate", "schema", "train"]`.

**`cards`** — `handlers.jl:35-41`. Params ignored entirely (`_::Any`). Returns
`{type: {label: String}}` from `Pipelines.CARD_SPECS`. VERIFIED, nine cards:

```json
{"cluster":{"label":"Cluster"},"dimensionality_reduction":{"label":"Dimensionality Reduction"},
 "gaussian_encoding":{"label":"Gaussian Encoding"},"glm":{"label":"GLM"},
 "interp":{"label":"Interpolation"},"rescale":{"label":"Rescale"},"split":{"label":"Split"},
 "streamliner":{"label":"Streamliner"},"window_function":{"label":"Window Function"}}
```

This is AgentGraph's `discover()` probe (`remote_procedure.py:431-445`) and therefore the health
check behind `GET /v1/services/dashi/health`. **Anything that breaks `cards` breaks AgentGraph's
service health, not just its pipelines.**

**`schema`** — `handlers.jl:43-49`. Params `{cards: [String], vars: [String]}`, both required
(bare `d["..."]`, so a missing key is a `KeyError` → `-32602`). Returns `{type: JSONSchema}`.
Serves the wrong dialect — [§4](#4-the-schema-dialect-gap).

**`train`** / **`evaluate`** — `handlers.jl:2-3`, both `execute_handler` with `train = true|false`
(`handlers.jl:15-33`). Params are the flat union of `DataFlow` and `Config` fields plus `from`:

```
id_var*, source*, destination*, schema, database, file_based, source_options,
destination_options, source_metadata, filters, nodes, groups, from
```

(`*` required — `DataFlow` has no defaults for those three, `entries.jl:113-115`.) Unknown keys are
silently ignored ([§0.2](#02-agentgraph-is-already-broken-against-main)).

Result: `(; entry.result, entry.run)` (`handlers.jl:31`), i.e.
`{"result": {"reports": [...]}, "run": {"_id", "time", "from", "trained", "directory"}}` — note the
nesting, `result.result.reports`, which AgentGraph's adapter unpicks
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:127-131`).

### 6.3 Error codes

`ExperimentTracking:src/api/json_rpc.jl:1-16`. Standard JSON-RPC 2.0 codes:

| Code | Name | Raised where |
|---|---|---|
| `-32700` | `parse_error` | `parse_json` — body is not JSON (`json_rpc.jl:70-77`) |
| `-32600` | `invalid_request` | envelope will not `make` into a `JSONRequest`; empty batch array; params neither object nor array (`json_rpc.jl:79-103`) |
| `-32601` | `method_not_found` | `get_method` (`json_rpc.jl:105-110`) |
| `-32602` | `invalid_params` | **`validate_method`** — anything thrown by the handler's validation phase (`json_rpc.jl:112-119`) |
| `-32603` | `internal_error` | **`handle_request`** — anything thrown by the thunk (`json_rpc.jl:121-129`) |

Messages are `"*<Default message>*\n<showerror output>"` (`json_rpc.jl:18-33`), asserted at
`test/api.jl:48-51`. The `*…*` markdown emphasis is deliberate and clients surface it verbatim.

> Curiosity worth one line, because it defeats grep: the enum literals use **U+2212 MINUS SIGN**,
> not ASCII hyphen — `parse_error = −32700` (`json_rpc.jl:3`, byte sequence `e2 88 92`). Julia
> accepts it as unary minus, and the emitted values are correct (`-32700` VERIFIED, and asserted at
> `test/api.jl:47`). But `grep -n '\-32700' src/` finds nothing. Harmless; worth normalising to
> ASCII while someone is in that file.

### 6.4 The request-validation split

The prompt asks about the split "described in the `parse_execute_params` docstring". That function
does not exist on `main` (§0.1); the docstring is at
`ds/file-mode-and-run-events:src/api/handlers.jl:17-26`. But **the split it describes is real on
`main`, generalised**: on the branch it was one function shared by `train` and `validate`; on `main`
it is a convention every handler follows, made routable by the probe middleware.

The contract, stated at `ExperimentTracking:src/api/handlers.jl:13-14`:

> Each handler first _validates_ input and returns an executable function (thunk).
> Call `api/v_` to also execute or `api/v_/probe` to only perform validation.

So a handler is `params -> thunk`, and the two phases have different error codes:

```
apply_handlers (json_rpc.jl:138-143)
  ├─ get_method       → -32601
  ├─ validate_method  → -32602   ← calls handler(params); everything here is validation
  └─ handle_request   → -32603   ← calls thunk(); everything here is execution
```

For `execute_handler` the validation phase is `handlers.jl:19-23`: parse the `DataFlow`, read
`from`, parse the `Config`, then **construct the filters and the pipeline** — which is where
`validate_pipeline_schema` runs (`entries.jl:131-134` →
`DashiBoard:Pipelines/src/group_api/dag.jl:18`). So card-schema validation, unknown-card-type
errors, duplicate node ids (`group_api/deps.jl:68`) and unresolvable group references are all
`-32602`, raised **before any database work**. Everything from the closure onward — SQL, training,
file I/O, registry insert — is `-32603`.

This is a good design and worth preserving verbatim through the refactor: it is why
`api/v1/probe` can honestly answer "would this run?", and why `01-decisions.md` §3's claim that
`SchemaValidationError` is the UI's error contract actually holds. `SchemaValidationError` carries
`(culprit, issue)` with culprit strings like `"card in node 3"` and `"group weather_vars"`
(`DashiBoard:Pipelines/src/group_api/schema.jl:60-69,89,96`) — that is what the UI must parse to
attach an error to a form field, and it is **prose, not structured data**. If the UI needs to
highlight a specific field, `SchemaValidationError` should gain a machine-readable path. Flagging
as a small, real cost of §3's error-contract requirement.

### 6.5 The `run_id` progress mechanism

**It does not exist on `main`.** Asked for the record: there is no `run_id` param, no event
vocabulary, no sink, and a client receives nothing until the single response arrives at the end of
the run. `train` on a real dataset is a long synchronous POST with no progress.

What exists is three **process-global** `ScopedValue` callbacks — `SELECT_CALLBACK`,
`TRAIN_CALLBACK`, `EVAL_CALLBACK` (`ExperimentTracking:src/ExperimentTracking.jl:30-32`), read in
`_execute` (`interface.jl:31-33`) and passed to Pipelines, which invokes them per node
(`DashiBoard:Pipelines/src/pipeline.jl:65,99`). They are installed by the embedder around
`HTTP.serve!` (`ExperimentTracking:scripts/server.jl:54-57`), so they are **per-process, not
per-request**: they fire for every concurrent run with no way to tell which. Also note
`evaljoin_many` runs nodes under `Threads.foreach` (`pipeline.jl:96`), so callbacks fire
concurrently and out of order.

The branch's design (`ds/file-mode-and-run-events:src/events.jl`) is the right shape and worth
adopting: opt-in via `run_id`, callbacks *wrapped* rather than replaced so an embedder's logging
survives, five events (`data_selected`, `node_trained`, `node_evaluated`, `run_finished`,
`run_failed`), payloads carrying node id/label/card type and never data, emission shielded by
`safe_emit` so a dead transport cannot turn a successful run into a `-32603`, and the transport
itself behind a package extension so Redis stays a weak dependency.

**For the UI this matters more than it might look.** With no progress mechanism, "Run" is a button
that hangs. If the canvas is to show per-node progress — which is the obvious thing for a
node-graph UI to do — this is a prerequisite, and it needs a browser-reachable transport (SSE or
WebSocket) that the branch's Redis sink does not provide. Recommend treating "run progress" as a
distinct, scoped piece of work rather than assuming it falls out of the merge.

### 6.6 `version`, not `jsonrpc` — confirmed, and it is a bug, not a decision

**Confirmed.** The envelope field is `version` on requests, successes and failures alike:
`JSONRequest` (`json_rpc.jl:35-40`), `JSONSuccess` (`json_rpc.jl:42-46`), `JSONFailure`
(`json_rpc.jl:57-61`) each declare `version::VersionNumber = v"2.0"`.

**Is it deliberate?** AgentGraph documents it as *"the envelope's version field is `version`, NOT
`jsonrpc`"* (`agentgraph:src/agentgraph/tools/remote_procedure.py:21`) — but that is a client
recording an observation, not evidence of intent here. Nothing in this repository — no comment, no
docstring, no commit message on `0891dca switch to JSON RPC (#18)` — states a reason. I can find
**no evidence it was a decision**, and three pieces of evidence that it was not:

VERIFIED behaviour:

```
params with NO version field       => {"version":"2.0.0","id":1,"result":{...}}
client sends version: "2.0"        => {"version":"2.0.0","id":2,"result":{...}}
client sends jsonrpc: "2.0" (spec) => {"version":"2.0.0","id":3,"result":{...}}
client sends version: "1.0"        => {"version":"2.0.0","id":4,"result":{...}}
```

1. **The field is never validated.** A request declaring `version: "1.0"` is accepted and answered
   as 2.0. It is parsed into a `VersionNumber` and then ignored — it has no function.
2. **The emitted value is `"2.0.0"`, not `"2.0"`.** `VersionNumber` serialises with its patch
   component. Even a client willing to look at `version` gets a value that is not the JSON-RPC
   version string. This looks like an unnoticed consequence of the `VersionNumber` type choice, not
   a deliberate dialect.
3. **A spec-compliant client already works by accident.** `jsonrpc: "2.0"` is an unknown key,
   ignored by `make`, and `version` defaults to `v"2.0"`. So *requests* are already compatible; only
   *responses* deviate.

**Recommendation: emit `jsonrpc: "2.0"` as a plain string, keep accepting both on input.** Point 3
means the input side needs no change at all and no client breaks. The output side is the only
deviation, it buys nothing, and it is the difference between "any JSON-RPC library works" and
"every client needs a custom parser" — which matters now that a browser is about to become a
client. If the project prefers to keep `version`, that is defensible, but it should then be an
actual decision, written down, and the value should at least be `"2.0"`.

### 6.7 Batching and notifications

Both implemented, neither documented outside the code.

- **Batch:** params may be a JSON array of request objects; each is handled independently and the
  responses returned as an array (`json_rpc.jl:91-98,145-149`; tested at
  `ExperimentTracking:test/rpc.jl:17-35`). Handy for the UI: `cards` + `schema` in one round trip.
- **Notifications:** a request with no `id` produces no response
  (`json_rpc.jl:142`). In a batch, notification results are filtered out and an all-notification
  batch yields `nothing` → **HTTP 204** (`json_rpc.jl:147-148`, `router.jl:12-14`). VERIFIED:
  `no id -> notification => nothing (HTTP 204)`.

  Worth knowing: this applies to `train` too. A `train` request with no `id` runs the pipeline,
  writes the destination, inserts a registry row — and returns `204` with no body, so the client
  never learns the run's `_id`. Not wrong, but a sharp edge for a UI that omits `id` by accident.

---

## 7. Multi-pipeline orchestration

### 7.1 The stated purpose — there isn't one

The prompt asks for "your stated purpose, which the lead session has not read." I have to report
that **there is nothing to read.** `ExperimentTracking:README.md` is three lines: a title and a CI
badge. There is no design document, no `docs/`, no module docstring
(`ExperimentTracking:src/ExperimentTracking.jl:1` is a bare `module`). The purpose has to be
reconstructed from the code, and I would rather say so than paraphrase `02-stack.md` back at the
lead session as though it were sourced from here.

`02-stack.md` says this package "orchestrates several pipelines over one source and records each run
in a registry." The second half is exactly right and is most of what the code does. **The first half
overstates what exists.** There is no orchestrator, no scheduler, no fan-out, no dependency between
runs. `execute` takes one `Config` and one `DataFlow` and produces one `Entry`
(`ExperimentTracking:src/interface.jl:115-130`). That is the entire unit of work.

What the package actually provides is **provenance**, not orchestration: a content-addressed,
queryable record of which configuration was run against which data flow, when, with what result, and
warm-started from which prior run. That is a coherent and useful thing to be, and it is the thing
the UI should be built to exploit.

### 7.2 How several pipelines over one source are expressed, scheduled and related

**Expressed:** by calling `execute` N times with the same `flow.source` and different `config`.
There is no batch API, no multi-config document, no `[[pipelines]]` section. Nothing in the code
knows that two runs share a source.

**Scheduled:** they are not. `execute` is synchronous and the JSON-RPC handler is synchronous
(`ExperimentTracking:src/api/json_rpc.jl:122`). Concurrency, if any, is HTTP.jl serving requests in
parallel — with no coordination, no queue, and a shared `Repository`. Note that scheduling *within*
one pipeline does exist and is real: `Pipeline` computes layers by height
(`DashiBoard:Pipelines/src/dag.jl:57-82`), and `foreach_layer` runs each layer's nodes in parallel
under `Threads.foreach` (`DashiBoard:Pipelines/src/pipeline.jl:37-50,62-66,96-101`). So the DAG is
scheduled; the *set of DAGs* is not.

**Related:** two mechanisms, and it is important not to confuse them.

1. **By query, implicitly.** `get_entries(registry, params)` matches on any subset of
   `ENTRY_COLUMNS` (`ExperimentTracking:src/queries.jl:72-76`), and `to_params` produces those
   params from any of the four structs (`entries.jl:149-150`). So `get_entries(reg,
   to_params(flow))` returns every run against that data flow, and `get_entries(reg,
   to_params(config))` every run of that configuration (`test/interface.jl:63,86`). **This is the
   "several pipelines over one source" relation** — it is a query, computed on demand, not a stored
   edge.
2. **By `Run.from`, explicitly.** The only stored relation between runs.

### 7.3 What `Run.from` means operationally

Narrower than "lineage". Precisely: **`from` is the id of the run whose fitted node weights this run
loaded.** Nothing more.

The mechanism, end to end:

- `execute(...; from::Maybe{Integer})` → `get_run(registry, from)` fetches that run
  (`ExperimentTracking:src/interface.jl:121`, `entries.jl:28-30`), throwing
  `ArgumentError("Entry with id $(_id) not found")` for an unknown id
  (`queries.jl:89-91`; asserted at `test/interface.jl:94`).
- In `_execute`, if `from_run` is present: `from = from_run._id` and
  `load_nodes!(pipeline.nodes, from_run)` (`interface.jl:42-45`).
- `load_nodes!` reads `model_<from_id>_<i>.jld2` from **the source run's `directory`** and
  `set_state!`s each node (`serialize.jl:20-31`, path at `serialize.jl:1-5`).
- Weights are only ever written when `train = true` (`interface.jl:128`).

Four operational consequences the UI must respect:

- **It is positional.** `load_nodes!` zips `nodes[i]` to `model_..._i.jld2` by index
  (`serialize.jl:29-31`). There is **no check that the two configs have the same nodes** — not by
  id, not by card type, not by count. Warm-starting a 3-node pipeline from a 5-node run loads the
  first three files into whatever nodes happen to be there; a card type mismatch surfaces as a
  deserialisation error at best, and silently wrong state at worst. Guarding this is a real
  robustness gap, and a UI offering a "warm start from…" picker should filter candidates to runs
  whose `config.nodes` match — which it can do, because it has both configs.
- **Only train runs are warm-startable.** `directory` is `nothing` for a pure evaluate
  (`entries.jl:23` comment; `test/interface.jl:89-92` asserts `node_path` throws). AgentGraph
  documents the same constraint for its users
  (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:122-125`).
- **It is not a data-flow edge.** `from` says nothing about whether this run's source is the prior
  run's destination. Chaining pipelines by feeding one's `destination` into the next's `source` is
  possible, but nothing records it — the relation is invisible to the registry.
- **It is not "derived from".** Two runs of the same config on different data have no `from` link
  at all.

### 7.4 §9's "additional capabilities built on top of the UI" — what they concretely are

`01-decisions.md` §9 says ExperimentTracking "reaches to it and builds its additional capabilities —
registry, run lineage, multi-pipeline orchestration — on top of that UI." Concretely, from what the
code can actually support today:

**Capability 1 — Run history.** A list of `Entry` rows: when, trained or evaluated, from which run,
against which source/destination, with reports. Everything needed exists:
`get_entries` and `get_entry_by_id` (`queries.jl:72-93`), `entries_from_table` (`entries.jl:186`).
*What it needs from the UI:* a table view and a detail panel. *What it needs from this package:* a
wire method. **There is none** — the registry is not exposed over JSON-RPC at all
(`handlers.jl:5-10`). Cost: a `runs` / `run` method pair, ~40 lines, plus a decision on filtering
and paging.

**Capability 2 — Load a past run's config into the canvas.** The registry stores the full `Config`
(`schema.jl:30-34`), so "open this run's pipeline" is exactly `01-decisions.md` §2's import path
pointed at a registry row instead of a file. Free, given capability 1.

**Capability 3 — Warm start.** A "start from run N" control that sets `from`. *Needs from the UI:*
a run picker, restricted to trained runs and — per §7.3 — to node-compatible configs. *Needs from
this package:* nothing new beyond capability 1.

**Capability 4 — "Have I run this before?"** The high-value one, and the one that is genuinely
already built. Because `Config` serialises canonically (`sort_keys = true`, §1.2) and `get_entries`
matches JSON equality, the UI can ask "does an entry exist with this exact config and this exact
flow?" before spending a run. *Needs from the UI:* calling it on the canvas's current document
before Run. *Needs from this package:* the same `runs` method, with a params filter.

**Capability 5 — Comparing several pipelines over one source.** This is §7.2's query relation made
visible: fix a `DataFlow`, list every `Entry` against it, put their `Result.reports` side by side.
*Needs from the UI:* a comparison view. *Needs from this package:* capability 1, plus — importantly
— **`Result` becoming useful.** Reports are positional `Vector{StringDict}` with no node
correlation (§1.1) and `entries.jl:144` is marked `# TODO potentially enrich Result`. A comparison
view over anonymous positional dicts is not much of a view. **Recommend adding node id and card
type to each report** as part of this work; the branch's `node_payload`
(`ds/file-mode-and-run-events:src/events.jl:51-57`) already shows the shape.

**The honest summary of §9:** capabilities 1–4 are small and mostly wiring, because the registry
already stores everything they need and only lacks a wire method. Capability 5 — the actual
"multi-pipeline orchestration" — is the one that does not exist and would be new design, not new
plumbing. §9's ordering (UI first, ExperimentTracking layers on top) is right and I would not change
it; I would just not describe orchestration as an existing capability being surfaced.

---

## 8. Source connection and artifacts

### 8.1 What a `DataFlow` source can be

Three modes, selected by `file_based` and `database`, at
`ExperimentTracking:src/interface.jl:47,69`:

| Mode | Condition | `source` is | `destination` is |
|---|---|---|---|
| **File** | `file_based = true` | a path or URI readable by a DuckDB reader | a path; written by `COPY ... TO` |
| **Table** | `file_based = false`, `database = nothing` | a table name in `repository`, optionally in `schema` | a table name; `CREATE OR REPLACE TABLE` |
| **External database** | `file_based = false`, `database` set | *intended:* a table in an ATTACHed database | *intended:* likewise | 

**The third mode does not work.** See §8.2 — this is a defect, found during this reconnaissance.

**File mode** is the richest and is what AgentGraph uses (`dashiboard.py:118-121`, `fixed_fields
{"dataflow.file_based": True}`). `source` is spliced into a reader call
(`ExperimentTracking:src/load.jl:13-16` → `DashiBoard:DataIngestion/src/readers/utils.jl:24-36`),
so anything DuckDB's `read_csv`/`read_parquet`/`read_json` accepts works: a local path, a glob, an
`s3://`/`https://` URI. Format is inferred from the extension
(`ExperimentTracking:src/load.jl:7` → `DataIngestion/src/load.jl:14-17`) with five registered
readers — `csv`, `tsv`, `txt`, `json`, `parquet` (`DataIngestion/src/load.jl:1-7`) — and can be
overridden via `source_options["format"]`. Remaining `source_options` are splatted as reader kwargs
(`interface.jl:49`), giving the UI access to the full DuckDB reader surface: `nullstr`, `delim`,
`types`, `header`, `skip`, `hive_partitioning` and ~20 more
(`DataIngestion/src/readers/csv.jl:1-30`, `readers/parquet.jl:1-8`). `ExperimentTracking:test/rpc.jl:53`
exercises `{"nullstr": "NA"}`.

**Table mode** materialises the source as a virtual table, applies filters via
`DataIngestion.select` with a `Select` transform down to `input_cols`, runs the pipeline, then
writes the destination with `CREATE OR REPLACE TABLE ... AS` (`interface.jl:70-95`,
`external_database.jl:34-41`).

**Postgres** is reachable in principle: `PostgresConfig` (user/password/host/port/dbname) from a
TOML file, `getURI` building a `postgresql://` string, and `attach` issuing
`ATTACH '...' AS "name" (TYPE postgres)` (`ExperimentTracking:src/external_database.jl:1-23`).
`in_database` then qualifies names as `"db"."schema"."table"` (`external_database.jl:25-32`). The
`ATTACH` happens **outside** the request, at server setup (`scripts/server.jl:51`), so a UI cannot
connect a Postgres database at runtime — it can only *name* one the server already attached. That
is a reasonable security boundary and worth keeping deliberately.

**One config or several sources?** **Exactly one.** `DataFlow` has a single `source::String`
(`entries.jl:114`). Multi-file input is only reachable through globs — `load_filtered` takes
`files::AbstractVector` (`load.jl:3`) but `_execute` always passes the one-element `[flow.source]`
(`interface.jl:50`). Joining two tables is not expressible; it would have to happen upstream, or as
a card. Worth stating plainly to the UI session: **"Connect source" is singular by construction**,
and the canvas should not imply otherwise.

### 8.2 DEFECT: the external-database mode silently does nothing

Found while answering §8. Reporting because §1 of `01-decisions.md` puts changes here in scope and
because it will bite the moment anyone points the UI at Postgres.

`_execute` branches (`ExperimentTracking:src/interface.jl:47,69`):

```julia
if flow.file_based
    ...
elseif isnothing(flow.database)
    ...   # this branch's body is the EXTERNAL-DATABASE code
end       # <- no `else`
```

There is no `else`. So `file_based = false` **and** `database` set matches neither branch: the
pipeline never runs and the destination is never written. Execution falls straight through to
`interface.jl:99-104`, which builds a `Run` with `trained = true`, a `Result` from untrained nodes,
and an `Entry` — and `execute` then inserts it into the registry (`interface.jl:126-129`) and calls
`save_nodes` on the untrained nodes.

**A no-op recorded as a successful training run.**

VERIFIED — control (`database = nothing`) versus the external-database path, same config, same
repository:

```
### A. control: database = nothing
  tables now: ["dst_a", "tbl"]
  dst_a written? true
  reports: 3  trained=true

### B. database = "no_such_db" (never ATTACHed), file_based = false
  RETURNED WITHOUT ERROR
  dst_b written? false
  entry.run.trained = true
  entry.result.reports = [{},{},{}]
  entry.flow.database  = "no_such_db"
```

A database name that was never ATTACHed produces no error at all — proof the branch never executes,
since any real attempt would fail on an unknown catalog.

**Introduced by `893fcb3` ("Better support for file based API (#19)").** `git log -L` shows the
pre-image was a three-way `if file_based / elseif isnothing(database) / else`. That commit replaced
the `elseif` branch's *body* with the former `else` body and deleted the `else` clause. The
surviving branch still threads `flow.database` through `in_database`
(`interface.jl:75,93`) where it is statically `nothing` — the fossil of the merge.

**Why no test caught it:** `test/external_database.jl` is five lines and only asserts the URI
string; `test/interface.jl` and `test/api.jl` exercise `database = nothing` exclusively.

**The fix is one line** — change `elseif isnothing(flow.database)` to `else`. The branch body
already handles both cases correctly, because `in_database(tbl, schema, nothing)` degrades to
`in_schema` (`external_database.jl:25-32`). Add a test with two ATTACHed DuckDB databases; no
Postgres server needed.

Note that `ExperimentTracking:scripts/server.jl:64-66` — this repository's own example — sets
`database = "postgres_db"` with `file_based` unset, and so demonstrates the broken path.

### 8.3 What a UI must collect to produce a valid `DataFlow`

Minimum: **`id_var`, `source`, `destination`** (`entries.jl:113-115`, the three fields with no
default). Then, by mode:

| Field | When | Note |
|---|---|---|
| `file_based` | file mode | AgentGraph fixes it `true` |
| `schema` | table mode | ignored in file mode |
| `database` | external db | see §8.2 |
| `source_options` | file mode | reader kwargs; the UI should expose at least `format` and, for CSV, `nullstr`/`delim` |
| `destination_options` | never | **throws if non-empty** (`interface.jl:57-59`) — the UI must not send it |
| `source_metadata` | **always, if validation is wanted** | see below |

**`source_metadata["cols"]` is the most important field for the UI and the least obvious.**
`initialize_pipeline` reads it and passes it as `available_cols`
(`ExperimentTracking:src/entries.jl:131-134`); it becomes `VariableConfig.cols` and hence the `col`
enum in every card schema (`DashiBoard:Pipelines/src/group_api/schema.jl:76-78,31`). **Absent, the
enum is `nothing` and column names are entirely unvalidated** (§4.3). VERIFIED: a card referencing a
nonexistent column passes validation without it. `ExperimentTracking:test/rpc.jl:79-95` is the test
that pins this: wrong `cols` → `-32602`, right `cols` → success, through the probe route.

So the "Connect source" step is not only for populating pickers, as `01-decisions.md` §2 says — its
output is also **the thing that makes validation meaningful**, and it must be sent on every
`train`/`evaluate`/`probe`/`schema` call even though it is not persisted in the `Config`.

### 8.4 What can be validated before running

Genuinely a lot, and all through one route. `POST api/v1/probe` runs the entire validation phase and
executes nothing (§6.4), which covers:

- `DataFlow` field presence and types (`DataFlow(d)`, `handlers.jl:19`);
- every card against its JSON Schema, in the group dialect, including card type, required fields,
  constraints, and — given `source_metadata["cols"]` — every column, node and group reference
  (`entries.jl:131-134` → `group_api/schema.jl:71-98`);
- group definitions against `group_schema` (`group_api/schema.jl:87-90`);
- duplicate node ids (`group_api/deps.jl:68`);
- unresolvable node/group references, as a `KeyError` from the index lookup
  (`group_api/deps.jl:46-47`);
- DAG well-formedness, including output-column collisions (`dag.jl:38-41`).

VERIFIED via `test/rpc.jl:79-95` and by my own runs.

**What cannot be validated before running:** filter validity (§5.3 — no schema, colnames unchecked);
source existence (file mode does no `isfile` check on `main` — the branch's `validate_file_flow` at
`ds/file-mode-and-run-events:src/load.jl:64-105` adds exactly this, and it is worth salvaging);
destination writability; and anything data-dependent (types, nulls, cardinality).

### 8.5 The parquet exchange

Both ends write parquet through DuckDB's `COPY`, and AgentGraph's docstring says so explicitly:
*"This is the same COPY ... TO mechanism ExperimentTracking.jl uses on the Julia side — both ends of
the DashiBoard integration write parquet through duckdb, which is the point of file-as-interface"*
(`agentgraph:src/agentgraph/tools/artifact_codecs.py:119-121`).

**Julia side**, `ExperimentTracking:src/interface.jl:60-67`:

```julia
sql, ps = DuckDBUtils.render_params(
    DuckDBUtils.get_catalog(repository),
    From(tbl) |> Select(args = Get.(output_cols))
)
DBInterface.execute(Returns(nothing), repository,
    "COPY ($(sql)) TO $(to_sql(flow.destination));", ps)
```

**Python side**, `agentgraph:src/agentgraph/tools/artifact_codecs.py:143`:
`con.execute(f"COPY _src TO '{p}' ({fmt_opts}{extra});")`, with `"parquet" => "FORMAT PARQUET"`
(`artifact_codecs.py:135`). Reads go through `read_parquet` (`artifact_codecs.py:98`).

Three details that matter:

1. **Julia specifies no `FORMAT`.** The Julia `COPY` has no options clause at all, so **DuckDB
   infers the format from the destination's file extension**. Parquet output therefore depends
   entirely on the filename ending in `.parquet`. AgentGraph guarantees this by declaring
   `suffix=".parquet"` on its `ArtifactOutput`
   (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:103-110`). It works, but it is an
   implicit contract held together by a filename — worth writing down, because a `destination` of
   `out.dat` silently produces CSV.
2. **`destination_options` exists but is rejected.** `interface.jl:57-59` throws
   `"destination_options are not yet supportd"` (sic — typo in source) for any non-empty value. So
   there is currently **no way to override the output format, compression or partitioning**. This
   is the natural place to fix detail 1: implement `destination_options` and pass `FORMAT PARQUET`
   explicitly. Small, and it removes a whole class of silent surprise.
3. **The output is projected, not the whole table.** `output_cols = union(get_output_vars(pipeline),
   [id_var])` (`interface.jl:37`), so the destination carries **only the pipeline's output columns
   plus `id_var`** — not the source columns. `test/interface.jl:108-110` asserts exactly this:
   `(:_percentile_partition, :_tiled_partition, :PRES_rescaled, :TEMP_rescaled, :No)`.

   **This contradicts AgentGraph's stated contract**, which describes the destination artifact as
   *"the same table plus the pipeline's output columns"*
   (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:112-114`) and
   `"parquet: source table + pipeline output columns"` in `02-stack.md`'s diagram. In **file mode
   that is not what is produced** — the source columns are absent, and a consumer must re-join on
   `id_var`. (In table mode the same projection applies, `interface.jl:91-94`.) Someone is wrong;
   the code and its test say the projection is real. **Flagging for the AgentGraph session** rather
   than assuming which side should change: either the docstring is stale, or file mode should
   `union` the source columns into `output_cols`. It is a one-line change here if the latter.

---

## 9. What the decisions cost this repository

Section by section through `01-decisions.md`. "Cost" is my estimate of work landing in
ExperimentTracking specifically; work landing in Pipelines, DataIngestion or the frontend is named
but not sized.

| § | Implies work here? | Cost | What |
|---|---|---|---|
| 1 Goals | scope only | — | Confirms changes here are in scope; §§0.1, 8.2 exercise that. |
| 2 The document the UI produces | **yes, blocking** | **~25 lines + tests** | `validate`/probe must return `{source_vars, output_vars}`. Nothing returns them today (§0.1, §4.4). §2's save-annotation story does not work without it. Plus my recommendation to add a `version` key to `Config` (§1.4). |
| 3 How card UI is derived | **yes** | **~10 lines** | "Dynamic enums are baked server-side … injected into `$defs` by `card_schema(key, variable_config)`" is precisely the `schema_handler` fix (§4.3). The Pipelines-side machinery already exists. |
| 4 Where presentation metadata lives | no | **zero** | `dashi` tags and deleting the TOML/`CardWidget` sidecars are Pipelines work. Richer schemas flow through `schema_handler` untouched. |
| 5 The canvas | **partly** | **~10 lines here** | `graphviz` for `GroupDiGraph` is Pipelines work and is currently a `MethodError` (§3.3). The endpoint here is trivial — *if* DashiBoard retires (§3.4). "No node positions stored" costs nothing: `Config` has nowhere to put them, which is a feature. |
| 6 Groups and the variable picker | **yes** | folded into §3 above | Requires the group dialect *and* serving `group_schema(variable_config)`, which nothing serves today (§4.3). |
| 7 Scope of the frontend work | no | **zero** | Retiring `frontend/` is DashiBoard's. |
| 8 Filters | **yes** | **1–2 days** | §5.2: filters are not annotated structs and cannot ride section 3's mechanism as-is. Needs a spec registry, StructUtils annotations, a tagged-union schema and a hand-written interval sub-schema. Plus a `filters` wire method so the UI can enumerate types, and implementing the `initialize_filters` TODO (§5.3). Bounds-from-`summarize` is the free part. |
| 9 How the three layers fit together | **yes, new design** | **~40 lines + design** | Capabilities 1–4 need one `runs`/`run` wire method pair over the existing registry queries. Capability 5 (comparison) needs `Result` to carry node identity — currently positional anonymous dicts (§7.4). |
| 10 Serving and origins | **yes** | **~40 lines + a parameter** | §2. An `assets` parameter on `get_router`, a `/**` handler, a MIME table, two cache rules, one containment check. |
| 11 Keep every mechanism replaceable | **yes, and easily missed** | **~20 lines** | See below. |
| 12 Still open | answered | — | §§0.1, 3, 4, 5 here. |

### The §11 cost that is easy to miss: there is no CORS handling at all

§11 requires one bundle to work "served by Julia (same origin, relative URLs) **and** served from
anywhere else (absolute URL, CORS configured)". The second half has no implementation here.

`ExperimentTracking:src/api/router.jl:8-11` sets exactly two response headers, `Content-Type` and
`Accept`. There is **no `Access-Control-Allow-Origin`, no `OPTIONS` handler and no preflight
support** anywhere in `src/` — verified by grep. The DashiBoard server has all of this
(`DashiBoard:DashiBoard/src/middleware.jl:1-22`); this package has none of it.

This is not only a production concern. **It bites in development immediately**: Vite serves the
frontend on `127.0.0.1:3000` (`DashiBoard:frontend/vite.config.mjs:6-9`) while the API is on
`:8080`. Every request from the dev server is cross-origin, every `POST` with
`Content-Type: application/json` triggers a preflight, and every preflight will fail against a
router with no `OPTIONS` route. **Anyone starting frontend work against ExperimentTracking will hit
this on their first request**, before any of the design questions in this brief matter.

Recommendation: add CORS as *configured* middleware — an explicit origin allow-list parameter on
`get_router`, defaulting to none — rather than copying DashiBoard's unconditional `"*"`
(`middleware.jl:1-7`). Same-origin production then sends no CORS headers at all, and development
sends them for `http://127.0.0.1:3000` only. That is §11's "changeable by configuration rather than
rebuild" applied to the server side, and it avoids inheriting a wildcard that is wrong the moment
anything is exposed.

### Summary of what lands here

Roughly **one week of focused work**, in this order:

1. **CORS + `assets` parameter** (§9 above, §2). Unblocks all frontend work. Half a day.
2. **`schema_handler` → group dialect, and serve `group_schema`** (§4.3). Removes a live correctness
   bug and satisfies §§3 and 6. Half a day.
3. **Probe returns `{source_vars, output_vars}`** (§4.4). Unblocks §2's save annotation. Half a day.
4. **Fix the `else` in `_execute`** (§8.2). One line and a test.
5. **Filter schema derivation** (§5.2). 1–2 days, the largest item, and the one §8 does not budget.
6. **Registry wire methods** (§7.4). ~40 lines plus paging decisions.
7. **The five capabilities** (§3), once §3.4 is decided. 2–3 days, mostly `fetch-data`.

Items 1–4 are small, independent and unambiguously correct; they can start immediately and I would
recommend they do, since three of them are bug fixes.

---

## Appendix A — defects found during reconnaissance

Four, none previously recorded. All verified by execution except A3, which is verified by name
resolution.

| # | Severity | Where | What |
|---|---|---|---|
| **A1** | **High** | `ExperimentTracking:src/interface.jl:69` | External-database mode is a silent no-op recorded as a successful trained run (§8.2). One-line fix. |
| **A2** | **High** |`ExperimentTracking:src/api/handlers.jl:45,47` | `schema` serves a dialect that rejects every config the server can run, and accepts configs it cannot (§4.1). |
| **A3** | Low | `ExperimentTracking:src/load.jl:6` | The default `table::AbstractString = TABLE_NAMES.source` references a binding that does not exist in this module. `TABLE_NAMES` is defined only in `DashiBoard:DataIngestion/src/load.jl:9-12`, is neither exported nor `public` (`DataIngestion/src/DataIngestion.jl:3-5`), and ExperimentTracking's import list is `using DataIngestion: Filter, selection_query, DataIngestion` (`ExperimentTracking:src/ExperimentTracking.jl:14`). VERIFIED: `isdefined(ExperimentTracking, :TABLE_NAMES) = false`. Dead today because `_execute` always passes `tbl` (`interface.jl:50`); an `UndefVarError` the first time anyone calls `load_filtered` with three arguments. |
| **A4** | Low | `ExperimentTracking:src/interface.jl:58` | Error message typo: `"destination_options are not yet supportd"`. |

Related but not defects, listed so they are not rediscovered: the U+2212 minus signs in the error
enum (§6.3); `version` serialising as `"2.0.0"` (§6.6); the projection/contract disagreement with
AgentGraph over destination columns (§8.5, detail 3) — that one needs the AgentGraph session, not a
fix here.

---

## Appendix B — verification method

Claims marked VERIFIED were executed against this repository's own test environment
(`julia --project=test`, Julia 1.12.6), not inferred from reading. Four scripts, in the session
scratchpad:

| Script | Establishes |
|---|---|
| `verify.jl` | `initialize_pipeline` yields a `GroupDiGraph`; `Pipelines.graphviz` `MethodError`s on it; the two `schema_definitions` methods produce different `$defs` (§3.3, §4.1) |
| `verify2.jl` | The two dialects reject each other's cards, both directions, using this repository's own `config.toml` card; `TABLE_NAMES` is not defined in this module (§4.1, A3) |
| `verify3.jl` | The external-database no-op, against a `database = nothing` control (§8.2, A1) |
| `verify4.jl` | Served method list; `validate` → `-32601`; `version` accepted/ignored/emitted as `"2.0.0"`; `jsonrpc` silently ignored; notification → 204; `load_options` dropped (§0.1, §0.2, §6.2, §6.6, §6.7) |

Two caveats on scope. Nothing was run against Postgres — A1 is demonstrated with an unattached
database name, which is sufficient to prove the branch never executes but does not tell us whether
the branch body is *otherwise* correct once reached. And all Pipelines behaviour was checked against
the **resolved** package (`~/.julia/packages/Pipelines/ruNcy`), not the DashiBoard working tree; see
§0.3 for why those differ and why the conclusions hold for both.

---

## Appendix C — for the other sessions

**DashiBoard (lead).** §0.1 is the one to read first: `02-stack.md`'s ExperimentTracking section and
§12 of `01-decisions.md` describe an unmerged branch, and the `validate` method §2 depends on does
not exist on `main`. §3.4 argues for retiring the DashiBoard server but flags server-side
visualization as an unresolved fork you should decide (§3.4, case-against point 1). §5.2 contradicts
§8's "nothing about them is hand-written" — the conclusion stands, the cost does not. §9 has the
per-section costing.

**AgentGraph.** Three things, all in §0.2 and §8.5: `validate` is `-32601` against `main`;
`load_options` is silently dropped because `main` renamed it to `dataflow.source_options`; and your
`ArtifactOutput` description says the destination is "the same table plus the pipeline's output
columns" while the code projects to output columns plus `id_var` only, dropping the source columns
(`ExperimentTracking:src/interface.jl:37`, asserted at `test/interface.jl:108-110`). Also, minor:
`discover()`'s docstring says "cards + their schemas" but it only posts `cards`
(`remote_procedure.py:431-445`) — which is fine by me, and is why the §4 schema change breaks
nothing of yours.

**nexus-weaver-pro.** Two facts that constrain the embed. `Config` is `{filters, nodes, groups}`
with no positions, no edges and no `DataFlow` (§1.1, §1.4) — `DashiboardPage.tsx`'s
`PipelineConnection` has no counterpart and cannot acquire one, since edges are *derived* from what
each node consumes (`DashiBoard:Pipelines/src/group_api/deps.jl:63-88`). And per §9, this server has
no CORS handling at all today, so an embed that is not same-origin needs the allow-list work
described there before it can make a single request.

---

## Appendix D — amendment: testing `01-decisions.md` §13 against what Pipelines can emit

Added after the renumbering, in response to the corrected `01-decisions.md` (§13, the served schema
profile) and `06-design.md` (A3, the keystone). §13 is a specification for the response my
`schema_handler` returns, so I checked it against what `card_schema` actually produces today. Five
findings, all VERIFIED by execution. Four make A3 larger than it looks; one is good news for A7.

None of this contradicts §13 — it is the right profile, and D1 and D5 are cases where §13 and §14
turn out to be fixing a bug that is already live rather than preventing a hypothetical one. The
point is only that A1 and A3 as scoped in `06-design.md` do not yet cover them.

### D1 — Field order is already lost, so §4's "form order from struct field order" is not achievable today

`composite_schema` builds `properties` as a `StringDict` = `Dict{String,Any}`
(`DashiBoard:Pipelines/src/structs/json_schema.jl:39,51`), which is unordered. It iterates
`fieldnames(T)` in declaration order (`json_schema.jl:45`) and then throws that order away.

VERIFIED on `GaussianEncodingCard`:

```
typeof(properties)   = Dict{String, Any}
struct field order   = [:method, :input, :n_components, :lambda, :suffix]
properties key order = ["method", "suffix", "lambda", "input", "type", "n_components"]
=> order preserved?  false
```

So §4's "form order from struct field order" describes something that does not survive schema
generation, and **A1 alone does not deliver it** — adding `title`/`description` to `dashi` tags
gives labels, not order. §13's `x-dashi-order` is therefore not belt-and-braces; it is the only
mechanism by which order can reach the renderer at all. Worth making explicit in A3, because
"preserve the existing order" and "capture an order that is currently discarded" are different
tasks, and only the second one is real.

### D2 — Method variants have no label to put in `oneOf: [{const, title}]`

§13 requires "Options carry their own labels: `oneOf: [{const, title}]`, never a bare `enum`". For
**card type** selection the title exists — `CardSpec(type, label, settings)`
(`DashiBoard:Pipelines/src/card.jl:282-295`). For **method variant** selection it does not exist
anywhere.

Method unions register through `@options T METHODS` (`Pipelines/src/method.jl:26-44`) against
dicts of the form `OrderedDict{String, Type}` — a key and a bare type, no label field. VERIFIED:

```
CLUSTERING_METHODS  = OrderedDict{String, Type}("kmeans" => KMeansMethod,
                        "dbscan" => DBSCANMethod, "affinity_propagation" => AffinityPropagationMethod)
CARD_SPECS entry    = CardSpec(ClusterCard, "Cluster", nothing)   # has .label
method has .label?  = NO — it is a bare Type: Pipelines.KMeansMethod

### what the variant selector emits today
{"type":{"enum":["kmeans","dbscan","affinity_propagation"],"type":"string"}}
```

A1 says "add `title` and `description` to the `dashi` tags on every card and **method struct**".
A `dashi` tag on a field of `KMeansMethod` titles *that field*; it cannot title the variant
`"kmeans"` itself, because the variant's name lives in the dict key, not in the struct.

So `oneOf: [{const, title}]` for methods requires a `MethodSpec` analogous to `CardSpec` — changing
seven `*_METHODS` dicts (`method.jl` callers at `cards/interp.jl:77`,
`cards/dimensionality_reduction.jl:32`, `cards/split.jl:36`, `dissimilarities.jl:186,187`,
`cards/gaussian_encoding.jl:42`, `cards/cluster.jl:93`) plus the four places that index them by
type: `choose_method` (`method.jl:5-16`), `get_metadata` (`method.jl:18-22`), the `@options` macro
body (`method.jl:28-42`) and `lower_simple_method` (`method.jl:56`). Mechanical, but structural,
and it is the difference between "nine dissimilarities" reading as `sqeuclidean` or as
"Squared Euclidean" in the UI. **Recommend adding it to A1 explicitly.**

### D3 — Variants are inlined today, so `$defs` + `$ref` is a restructure, not an addition

`tagged_schema` emits one inlined `{if, then}` per variant into `allOf`
(`json_schema.jl:56-69`). VERIFIED on `cluster`: `allOf length = 3`, and the card's top-level
`$defs` holds only the variable definitions — no variant is a `$def`. §13's "`$defs` + `$ref` for
variants, not inlining" therefore rewrites `tagged_schema`'s output shape. The payload argument
§13 gives is real: `DISSIMILARITY_METHODS` has nine entries and is reachable from more than one
method.

**Quantified, because it turns out to be the weakest of the five and should be weighted
accordingly.** VERIFIED sizes of one `schema` response carrying all nine cards:

```
  cluster                      8607 bytes      (the worst case)
  interp                       6668 bytes
  gaussian_encoding            5053 bytes
  ... six others               3634-4596 bytes each
  TOTAL (all 9 cards)         44548 bytes   <- one `schema` response
  "minkowski" appears 8x and "sqeuclidean" 5x inside the cluster schema alone
  DISSIMILARITY_METHODS: 9 variants;  METRIC_METHODS: 7
```

44 KB over a local connection is not a payload problem, so §13's payload argument does not carry
much weight here. Its *other* argument does: with variants inlined, a renderer cannot tell that the
`sqeuclidean` under `KMeansMethod` and the one under `DBSCANMethod` are the same thing, so it
cannot share a component or a cache between them. **Treat D3 as a legibility and identity fix, not
a size fix** — it is a real restructure of `tagged_schema`, but it is the one item of the five that
could be deferred without anything breaking.

### D4 — The profile must declare its draft, because `$ref` semantics changed and the schema relies on the old ones

**This is the one I would act on first, and it is invisible until a browser validates.**

The emitted schema has **no `$schema` key** (VERIFIED), so its draft is implicit. It contains
`$ref` alongside contradictory sibling keywords. `ClusterCard.weights::Union{String,Nothing}`:

```
weights schema = {"$ref":"#/$defs/variable","type":"string"}
$defs/variable = {"allOf":[{"if":{"type":"object"},"then":{...}}, ...]}   # object|array
```

The sibling `"type":"string"` and the `$ref`'s object/array constraint cannot both hold. Which one
applies is **draft-dependent**:

- **draft-07**: `$ref` *replaces* all sibling keywords — the `type` is ignored.
- **draft 2019-09 / 2020-12**: `$ref` is an assertion *among* siblings — both apply, and the field
  becomes **unsatisfiable**.

VERIFIED that the Julia side takes the first reading:

```
Julia verdict, OBJECT weights vs {$ref->object/array, type:"string"}:
    ACCEPTS => sibling `type` IGNORED (draft-07 $ref semantics)
minimal repro {"w":{}} : ACCEPTS (sibling ignored => draft-07)
```

So `validate_pipeline_schema` passes documents that a modern browser-side validator — Ajv defaults
to 2020-12 for new schemas — would reject as unsatisfiable, on **every card field carrying a
`JSON_VARIABLE`/`JSON_VARIABLES` tag**, which is most of them. Server and browser would disagree
about the same document, which is precisely the failure §13's closed profile exists to prevent.

The collision has a clean cause: `schema_from_type(T)` derives `"type" => "string"` from the Julia
field type, then `merge!(schema, config)` adds the tag's `$ref` on top (`json_schema.jl:24-32`).
The derived `type` describes the **resolved** field (`inputs::Vector{String}` after the group
selectors are resolved away) while the `$ref` describes the **document** form — they genuinely
describe different things, so neither is wrong; they just must not sit in one schema object.

Three fixes, in increasing order of correctness:

1. Drop the derived `type` when the tag supplies a `$ref` — one condition in
   `schema_from_type(T, config, default)`.
2. Wrap as `allOf: [{$ref: ...}]` so no keyword is a sibling of `$ref`, valid under every draft.
3. **Emit `"$schema"` explicitly in the `dashi/1` profile** and pin it. §13 already declares a
   dialect version; it should declare the JSON Schema draft too, because "dashi/1" says nothing
   about how a validator resolves `$ref`.

I recommend 1 **and** 3 — the fix and the guard. This is cheap now and, per §13's own reasoning
about retrofits, expensive later.

**Correction, from the DashiBoard session executing the browser half I could not observe from
Julia.** Ajv 8.20 against the group-dialect target gives, for *both* declared drafts: target alone
VALID, `$ref` with no sibling VALID, `$ref` + `type:"string"` sibling **INVALID**. Ajv 7+ applies
siblings regardless of the declared draft. So my framing above — "browsers default to 2020-12" — is
too weak twice over: the breakage does not depend on which draft the browser is told to use, and
draft-07's literal `$ref`-replaces-siblings rule is now effectively a **JSONSchema.jl-specific
behaviour** rather than an old-but-respected standard. Consequence for the fix: **option 3 alone
does not work** — pinning `$schema: draft-07` buys determinism from validators that honour it, but
Ajv will reject regardless. Option 1 (drop the sibling) is the fix; option 3 is the guard. Their
A3a is reworded to lead with dropping siblings, which is correct.

### D5 — §14's nullable rule is already violated, and it breaks the Card round trip

§14 rule 2 says never wrap a nullable in `anyOf`; use `type: ["string","null"]`. Today the schema
does **neither** — a nullable field emits a non-nullable type, and the serialiser emits `null` into
it. VERIFIED:

```
### Card -> get_metadata round trip (cluster)
in  = {"inputs":["a","b"],"method":{"classes":3,"type":"kmeans"},"type":"cluster"}
out = {"inputs":["a","b"],"method":{"classes":3,"dissimilarity":{"type":"sqeuclidean"},
       "iterations":100,"seed":null,"tol":1.0e-6,"type":"kmeans"},"output":"cluster",
       "partition":null,"type":"cluster","weights":null}
null-valued keys emitted: ["weights", "partition"]

round-tripped => INVALID (path=[method][seed] reason=type val=integer)
```

`schema_from_type` maps `Union{Int,Nothing}` to `"integer"` and drops the `Nothing`
(`json_schema.jl:11-16`), so `seed: null` fails. Omitting the field is fine — `is_required` is
false for nullables (`json_schema.jl:30`) — but **explicitly passing `null` is rejected**, and
`StructUtils.lower` passes it explicitly.

**Refinement, checked after first writing this: the schema itself is internally consistent.**
A card seeded entirely from the schema's own defaults VALIDATES, and a nullable with a `nothing`
default emits *no* `default` key rather than `default: null`, because `schema_from_type` skips it
(`json_schema.jl:27`). So **A3 has no defaults problem** — the inconsistency is strictly between the
schema and the *serialiser*: `KMeansMethod.seed` emits `{"minimum":0,"type":"integer"}`, no default
and no null permitted, while `lower()` writes `seed: null`. VERIFIED:

```
### Does a card seeded ENTIRELY from the schema's own defaults validate?
  seeded card = {"inputs":{"cols":["a"]},"method":{"classes":3,"type":"kmeans"},
                 "output":"cluster","type":"cluster"}
  => VALID
### lower() on the same card
  nulls emitted by lower(): ["partition", "weights"]      nested method nulls: ["seed"]
```

Two consequences worth recording:

- §14 rule 2's fix should be stated as *make nullables actually nullable* (`type: ["integer","null"]`),
  not only as "avoid `anyOf`". The `anyOf` diagnostic problem is real but it is not the bug that is
  live here.
- **`get_metadata` output is not a valid document**, on two counts: the nulls above, and `inputs`
  coming back in resolved form (`["a","b"]`) rather than document form (`{cols: [...]}`), because
  the group vocabulary is resolved away by `Context` before any `Card` is constructed
  (`Pipelines/src/group_api/deps.jl:109,132`). **The UI must never reconstruct the saved document
  from Cards** — the authored JSON in the registry's `Config` is the only copy of the document form.
  `01-decisions.md` §2's "saves, imports and round-trips" therefore has to mean round-tripping the
  stored JSON, which works, and not Card reconstruction, which does not. Worth saying in §2, since
  "round-trip" reads as though either would do.

  Not currently a live bug here: ExperimentTracking imports `get_metadata`
  (`ExperimentTracking:src/ExperimentTracking.jl:17`) but never calls it. It is a trap for whoever
  builds "export the current pipeline".

### D6 — Good news for A7: the JSON Pointer is derivable, and the options come free

`JSONSchema.validate` returns a `SingleIssue` with exactly the fields A7 needs. VERIFIED:

```
typeof = JSONSchema.SingleIssue
  x        = "not_a_method"
  path     = "[method][type]"
  reason   = "enum"
  val      = ["kmeans", "dbscan", "affinity_propagation"]
```

`path` converts to a JSON Pointer mechanically (`[method][type]` → `/method/type`), `reason` is the
failing keyword, `val` is the constraint — and for an `enum` failure that *is* the list of valid
options, which is what a form needs to render a correction. So A7 is mostly plumbing
`SingleIssue` into `SchemaValidationError` (`Pipelines/src/group_api/schema.jl:60-69`), which today
keeps only a prose `culprit` and the raw issue. The `related` array for the `weights`/`inputs` pair
is the only part with no existing source.

### D7 — A scoping note on the plan: part of A3 lands in ExperimentTracking, not Pipelines

`06-design.md` puts "emit the `dashi/1` profile" entirely in Track A (Pipelines). But three of §13's
requirements are properties of the **response envelope**, which `schema_handler` builds, not
`card_schema`:

- `dialect: "dashi/1"`;
- `context: {nodes, groups, cols}` echoing the specialisation;
- `cards` and `filters` as sibling keys of one response.

Today `schema_handler` returns a bare `{cardtype: schema}` map
(`ExperimentTracking:src/api/handlers.jl:47`) with no envelope at all. That work is real, it is
mine, and it is not in Track B. It folds naturally into **B2**, which is already touching that
function — so B2 becomes "group dialect **plus** the `dashi/1` envelope, and serve `group_schema`",
and it acquires a dependency on A3 having settled the profile's shape. Suggest updating B2's row
rather than adding an item; the cost stays about half a day.

### D8 — Answer: the source-free probe. Placeholders work today; a document-level method is the right fix

Asked by the DashiBoard session after AgentGraph declined to guess. Recorded open in
`01-decisions.md` §2 and in `06-design.md`'s decisions table.

**The finding that settles it: the validation phase never reads `source`, `destination` or
`id_var`.** `execute_handler`'s validation phase is five statements
(`ExperimentTracking:src/api/handlers.jl:19-23`) — `DataFlow(d)`, `get(d, "from")`, `Config(d)`,
`initialize_filters(config, flow)` which ignores its flow argument
(`ExperimentTracking:src/entries.jl:129`), and `initialize_pipeline(config, flow)` which reads
**only** `flow.source_metadata["cols"]` (`entries.jl:131-134`). The three required fields are
constructed and then not consulted until execution.

VERIFIED end to end, through the real probe route:

```
### 2. Omitting id_var/source/destination entirely
  REJECT -32602: *Invalid params* | TypeError: in typeassert, expected String, got a value of type Nothing
### 3. Empty-string placeholders
  ACCEPT
### 4. Placeholders + a WRONG column (does validation still bite?)
  REJECT -32602: Schema Validation Error for group weather | path: [cols][1]
### 5. Nonsense placeholders that could never resolve  ("/nonexistent/nope.parquet")
  ACCEPT
### 6. Does the probe touch the registry or filesystem?
  weights dir after all probes: String[]      registry rows after all probes: 0
```

So full pipeline validation still bites with placeholders in place (case 4), and the probe writes
nothing (case 6).

**Short answer: pass placeholders — `id_var`, `source` and `destination` all `""` — and nothing is
lost today.** Zero code change, and the UI is not blocked.

**Do not relax the fields.** `DataFlow`'s three required fields are the only thing making a
malformed `train` fail as `-32602` before any work; relaxing them to `Maybe{String} = nothing` moves
that failure to `-32603`, deep in SQL after selection has already run. It also collides with the
registry: `Column(:source, "VARCHAR")` is NOT NULL (`ExperimentTracking:src/schema.jl:38`), so a
null source fails at INSERT and the relaxation would need an execution-phase check re-added anyway.
That is weakening the real path to serve the probe path, for no gain.

**But placeholders are an interim, not the answer**, because they conflate two different questions:

1. *"Would this whole request run?"* — legitimately needs a real `DataFlow`. That is the probe on
   `train`/`evaluate`, and it should stay strict.
2. *"Is this document well-formed against these column names?"* — has nothing to do with a data
   flow. `01-decisions.md` §2 says the saved document is **source-agnostic**; this is the question
   the authoring UI actually asks, and it should not have to invent a source to ask it.

Conflating them is exactly what forces the placeholder convention, and a magic `""` is undiscoverable
and one copy-paste away from reaching `train`, where an empty `destination` names a table `""`.

**Recommendation: a document-level wire method**, `{cards?, nodes, groups, filters, cols}` →
`{valid, source_vars, output_vars}`, constructing no `DataFlow` at all. ~15 lines, and **no second
validator**: it calls the same `initialize_filters` and `initialize_pipeline`, so the drift the
branch's `validate` risked does not arise — it is a second *caller* of one validator, not a second
validator. `cols` sits top-level there, where it is honest; `source_metadata["cols"]` stays the
spelling on `train`/`evaluate`, where it genuinely is metadata about a source.

**This is the same work as B3.** B3's deliverable is `{source_vars, output_vars}` and this method's
return value is `{valid, source_vars, output_vars}` — one change, two entry points. They should land
together, and B3's row should say so.

**Two asides from the same test run:**

- The error for a missing required field is poor: `TypeError: in typeassert, expected String, got a
  value of type Nothing` **does not name the field**, and forgetting one is the most likely client
  mistake. `make` raising per-field would be a small, high-value fix in the same commit.
- Case 5 confirms nothing checks path validity on `main`. The branch's `validate_file_flow`
  (`ds/file-mode-and-run-events:src/load.jl:64-105`) is the missing piece, and it belongs on the
  *request* probe (question 1), never on the document method (question 2).

**On B3's priority:** the DashiBoard session reports AgentGraph is switching to the probe route and
that the switch is a hard prerequisite on B3, in that order. Confirmed from this side — the probe
returns `{"result": null}` today (`ExperimentTracking:test/api.jl:26` asserts exactly that), so a
client switching first would call `.get("source_vars")` on `None`. **B3 must land and be released
before AgentGraph switches**, not merely before the save-annotation story.
### D9 — Executed confirmation of A3a's column-enum claim, and its boundaries

The DashiBoard session established by reading that the column enums sit on the `$ref` *target*, so
AgentGraph's `source_metadata` fix buys real checking, and asked for execution to close the loop.
This environment is instantiated, so here it is. **The claim holds, structurally and behaviourally.**

**Structurally — the enum lives once, at the target.** VERIFIED on the `rescale` card schema built
with `VariableConfig(nodes=["partition"], groups=["weather"], cols=["No","PRES","TEMP"])`:

```
$defs/col         = {"enum":["No","PRES","TEMP"],"type":"string"}
$defs/node        = {"enum":["partition"],"type":"string"}
$defs/group       = {"enum":["weather"],"type":"string"}
property `inputs` = {"$ref":"#/$defs/variables","type":"array"}
"No" appears 1x, "PRES" 1x, "TEMP" 1x  — in the WHOLE card schema
```

Each column name appears exactly once in the entire schema. The chain is two hops:

```
property -> $defs/variables -> (object branch) .properties.cols
         -> {"items":{"$ref":"#/$defs/col"},"minItems":1,"type":"array"} -> $defs/col
```

and `through` resolves the same way to `$defs/node`
(`DashiBoard:Pipelines/src/group_api/schema.jl:15-18,29-31`, `structs/card_schema.jl:65-67`).
So specialising a schema to a pipeline state writes each vocabulary in one place, which is what
makes A3d's `$defs` restructure for *variants* consistent with what already happens for *variables*.

**Behaviourally — it converts ACCEPT into REJECT.** VERIFIED through the real probe route, each
case run twice, without and with `source_metadata["cols"]`:

```
                                            no cols:        with cols:
card inputs {cols:[GOOD]}                   ACCEPT          ACCEPT
card inputs {cols:[BAD]}                    ACCEPT          REJECT
group cols [BAD]                            ACCEPT          REJECT
card group_by {cols:[BAD]}                  ACCEPT          REJECT
unknown node ref {nodes:[BAD]}              REJECT          REJECT
unknown group ref {groups:[BAD]}            REJECT          REJECT
```

Two things worth separating, because they behave differently:

- **`cols` is the only vocabulary the caller supplies**, and without it the enum is absent and every
  column name passes (§4.3). That is the gap `source_metadata` closes, and it closes it for card
  fields *and* group definitions.
- **`nodes` and `groups` are always checked**, with or without `source_metadata`, because
  `validate_pipeline_schema` derives them from the document itself — `get_id.(nodes)` and
  `keys(groups)` (`DashiBoard:Pipelines/src/group_api/schema.jl:76-78`). Dangling node and group
  references were never affected by the gap.

**The boundaries, which are the actionable part.** VERIFIED that two things are *not* covered, with
or without `cols`:

```
filter on a nonexistent column              ACCEPT          ACCEPT
id_var not among cols                       ACCEPT          ACCEPT
```

Filters because `initialize_filters` ignores its `DataFlow` and no filter schema exists (§5.2, §5.3);
`id_var` because it is a `DataFlow` field and never reaches `validate_pipeline_schema` at all.

**So AgentGraph's client-side preflight checks on `id_var` and `filters[i].colname`
(`agentgraph:src/agentgraph/tools/platform/dashiboard.py:63-66`) are not made redundant by the
server-side improvement — they are currently the only thing covering those two paths.** Worth
saying explicitly to that session, since "the server now does real column checking" is a natural
reason to retire client-side duplicates, and here it would silently remove the only coverage. They
stay until the filter schema work (A6/B5) lands, and `id_var` stays uncovered even then unless
something checks it against `source_metadata["cols"]` — a three-line addition to
`initialize_filters`' TODO neighbourhood, and arguably the same commit.
### D10 — `x-` keys need no plumbing in the output; but A1 as scoped will break `Card` parsing

Asked by the DashiBoard session: do `x-dashi-order` and `x-dashi-discriminator` pass through
`json_config`/`nonnothing_dict` unchanged, or is new plumbing needed? Short answer first, then the
larger thing the check turned up.

**The answer: the output side needs no plumbing; only the typed helpers are closed.** VERIFIED:

```
json_config      REJECTED: MethodError (unsupported keyword)
json_string      REJECTED: MethodError (unsupported keyword)
json_array       REJECTED: MethodError (unsupported keyword)
json_number      REJECTED: MethodError (unsupported keyword)
json_object      REJECTED: MethodError (unsupported keyword)
nonnothing_dict  ACCEPTED -> {"x-dashi-order":["a","b"]}
```

The five typed wrappers have closed keyword lists (`json_schema.jl:90-161`), so an `x-` keyword is a
`MethodError`. The primitive underneath them, `nonnothing_dict(; kwargs...)` (`json_schema.jl:77`),
already accepts arbitrary keys and stringifies them correctly. And schemas are plain mutable
`StringDict`s, so assignment after construction is the path of least resistance. VERIFIED that it
survives everything downstream:

```
survives JSON round trip: true / true
emitted: "x-dashi-order":["method","group_by","inputs","targets","partition","suffix","target_suffix"]
good card => VALID          bad col => INVALID (still caught)
```

`JSONSchema.jl` ignores unknown `x-` keywords and keeps validating correctly, as JSON Schema
requires. So: assign post-construction in `composite_schema`/`tagged_schema`, or add a `kwargs...`
passthrough to `json_config` alone. Either is a one-liner, and neither is blocking.

Both keys are object-level anyway — `x-dashi-order` belongs on the object `composite_schema` emits,
`x-dashi-discriminator` on the union `tagged_schema` emits — so neither needs to travel through a
field's `dashi` tag at all. **Which is fortunate, because tags are where the hazard is.**

#### The larger finding: `dashi` tags are compared by equality, so A1 breaks the singular-variable lift

`StructUtils.lift(::DashiStyle, ::Type{String}, x::AbstractVector, tags)`
(`DashiBoard:Pipelines/src/structs/style.jl:13-30`) converts a one-element vector into a `String`,
and gates that on `get_dashi(tags) != JSON_VARIABLE` — an **equality comparison against one exact
dict**, `{"$ref":"#/$defs/variable"}`. Any key added to such a tag makes the comparison false and
the lift throw.

That lift is not an edge case. It is the normal path by which a group-API selector lands in a
singular variable field. VERIFIED on this repository's own example config:

```
as authored: {"nodes":["partition"]}
after Context resolution, RescaleCard.partition = "_tiled_partition" ::String
    field is declared ::Union{Nothing, String}

tag = JSON_VARIABLE                    -> ("x", nothing)
tag = JSON_VARIABLE + title (A1's job) -> THROWS ArgumentError
```

`Context` resolves `{nodes: ["partition"]}` to the one-element vector `["_tiled_partition"]`
(`DashiBoard:Pipelines/src/group_api/deps.jl:107,109`), and the lift is what turns it into the
`String` the field declares. **Twelve fields across eight card files are tagged exactly
`dashi = JSON_VARIABLE`** — `weights` and `partition` on `glm.jl:197,198,236,237`,
`dimensionality_reduction.jl:49`, `rescale.jl:114`, `cluster.jl:111,112`,
`streamliner.jl:118`, `interp.jl:92,94`, and `input` on `gaussian_encoding.jl:89`.

A1 is "add `title` and `description` to the `dashi` tags on every card and method struct". Adding a
`title` to any of those twelve makes its tag `{"$ref": ..., "title": "..."}`, the equality fails,
and **every config using a selector for that field stops parsing** — including
`ExperimentTracking:test/static/configs/config.toml:36`, which is `partition = {nodes = ["partition"]}`
on exactly such a field.

It fails loudly (`ArgumentError` from `Card` construction, surfacing as `-32602`) rather than
silently, and the test suite would catch it. But it will read as "adding a label broke the parser",
which is a confusing half-hour, and it lands on A1 — the item everyone will assume is mechanical.

**Fix, and it is small: compare on the `$ref` rather than on the whole dict.** Something like
`get(get_dashi(tags), "\$ref", nothing) == JSON_VARIABLE["\$ref"]` at `style.jl:14`. That makes the
gate depend on the field's *type identity* — which is what it was always trying to express, and the
same principle §4 uses when it says the renderer dispatches on a `$ref` to a named `$def` — instead
of on the tag being byte-identical to a constant. **Recommend doing it as A1's first commit, before
any title is added**, so the twelve fields can then be annotated freely.

**Checked for siblings of this pattern, and there are none.** `get_dashi` has exactly two call
sites in Pipelines: the gate at `style.jl:14`, and `composite_schema`'s merge at
`json_schema.jl:47`, which merges whatever the tag holds and is indifferent to extra keys.
`JSON_VARIABLES` and `JSON_NONEMPTY_VARIABLES` are only ever *used as values*
(`structs/card_schema.jl:29,30`, `group_api/schema.jl:50`), never compared. So `style.jl:14` is the
single occurrence, and the fix is genuinely one line. `style.jl` is also byte-identical between the
resolved package and the DashiBoard working tree, so this applies whichever copy A1 is written
against (cf. §0.3).
### D11 — Re-run of every result against the working-tree Pipelines, closing §0.3's caveat

The DashiBoard session correctly observed that my executed results ran against
`~/.julia/packages/Pipelines/ruNcy` (§0.3) and that while the schema files are byte-identical,
`group_api/deps.jl` and `group_api/dag.jl` are not — and D9's ACCEPT/REJECT table exercises exactly
those. That caveat is now closed, without waiting on the dev-path decision.

**Method: a throwaway environment in the session scratchpad** whose `[sources]` dev-pin
DataIngestion, DuckDBUtils, Pipelines, StreamlinerCore and ExperimentTracking to the working trees.
It modifies neither repository — no `Project.toml` change, no `~/.julia/dev` entry, and
ExperimentTracking's tree stays clean. It resolved and precompiled in 15 seconds. Confirmed it is
really the working tree before trusting anything:

```
pkgdir(Pipelines) = /home/dariosarra/Documents/Limen/DashiBoard/Pipelines
group_api/dag.jl uses `dependency_graph(node_configs, group_configs)`?  true
```

(that call signature exists only in the working tree; the resolved copy uses
`Configuration(nodes, groups) |> parse_deps!`).

**D9 reproduces row for row:**

```
                                        no cols:   with cols:
card inputs {cols:[GOOD]}               ACCEPT     ACCEPT
card inputs {cols:[BAD]}                ACCEPT     REJECT
group cols [BAD]                        ACCEPT     REJECT
card group_by {cols:[BAD]}              ACCEPT     REJECT
unknown node ref                        REJECT     REJECT
unknown group ref                       REJECT     REJECT
-- boundaries --
filter on nonexistent column            ACCEPT     ACCEPT
id_var not among cols                   ACCEPT     ACCEPT
```

Identical to the resolved-package run. **The boundary warning in D9 therefore holds against the
code being shipped**, which is the part that mattered — AgentGraph's preflight on `id_var` and
`filters[i].colname` is still the only coverage those two paths have.

**And the two other findings that touched divergent files also reproduce:**

```
§3.3  enriched_digraph = Pipelines.GroupDiGraph{Int64};  graphviz => THREW MethodError
§4.1  flat (served)              REJECTS   <- the repo's own example card
      VariableConfig (validated) ACCEPTS
```

So A4 and B2 are both still real against the shipping code.

**Why it reproduces, for the record.** Both trees call `validate_pipeline_schema` as the *first*
statement of `Pipeline(nodes, groups, cols)` — resolved at `group_api/dag.jl:42`, working tree at
`group_api/dag.jl:18` — before any of the code that differs. And every file
`validate_pipeline_schema` reaches is byte-identical across the two trees:
`group_api/schema.jl`, `structs/card_schema.jl`, `structs/json_schema.jl`, `structs/style.jl`.
The divergence is entirely downstream of the schema verdict, which is why a refactor of
`deps.jl`/`dag.jl` could not move any of these rows.

**A note on what this does and does not substitute for.** This closes the *verification* gap: any
result in this brief can now be re-checked against shipping code on demand, cheaply. It is not a
substitute for the dev-path change in `ExperimentTracking:Project.toml:23-27` — that is what makes
a Pipelines edit visible to ExperimentTracking's own environment, tests and CI, and it remains item
zero of `06-design.md`. But it does mean **verification is no longer blocked on that decision**, so
the two can be sequenced independently.
### D12 — A7's composition-keyword row for JSONSchema.jl, measured

Asked by the DashiBoard session: inside a composition keyword, does `JSONSchema.validate` return the
failing leaf, a combinator summary, or both? Measured against the **working tree** (D11's
environment), so this describes shipping code.

**Headline: our union shape leaks nothing.** `allOf` and `if`/`then` both propagate the leaf issue
verbatim, so the exact case asked about comes back as a leaf:

```
classes=0, minimum:1                 path="[method][classes]"           reason=minimum  val=1
THREE levels: kmeans>minkowski>p=0   path="[method][dissimilarity][p]"  reason=minimum  val=1
weighted_minkowski missing weights   path="[method][dissimilarity]"     reason=required val=["weights"]
bad variant name                     path="[method][type]"              reason=enum
                                     val=["kmeans","dbscan","affinity_propagation"]
```

Confirmed from source, which is why this is a property and not a coincidence:
`_validate(..., ::Val{:allOf}, ...)` returns the inner `ret` unchanged
(`JSONSchema/qhs1I/src/validation.jl:143-152`), and `_if_then_else` returns
`_validate(x, schema["then"], path)` (`validation.jl:238-247`). Neither constructs a `SingleIssue`
of its own. Only `anyOf` (`:154-161`), `oneOf` (`:164-179`) and `not` (`:181-187`) build summaries.

**So the row for A7's table is:**

| | `allOf` | `if`/`then` | `anyOf` | `oneOf` |
|---|---|---|---|---|
| Ajv 8 (browser) | — | **leaks** | **leaks** | — |
| Python jsonschema | — | never surfaces | **leaks** | — |
| **JSONSchema.jl** | **propagates** | **propagates** | leaks | **leaks** |

Which inverts the useful part twice over: **AgentGraph's offender (`anyOf`) does not occur in a
single shipped card schema**, and Ajv's offender (`if`/`then`) is precisely what our unions are
built from and is harmless here. Measured occurrence counts across all nine cards:

```
split      allOf=5  oneOf=6  if=9        cluster    allOf=6  oneOf=6  if=25
rescale    allOf=3  oneOf=6  if=6        interp     allOf=4  oneOf=6  if=13
...                                      anyOf: 0 in every card
```

**The one real offender is `oneOf`, and it is the variable picker.** Every card carries exactly six,
all from `variable_item_schema`'s `oneOf: [required nodes | required groups | required cols]`
(`DashiBoard:Pipelines/src/group_api/schema.jl:20-25`) — §6's picker, the component reused
everywhere. Measured:

```
two selectors at once {cols+nodes}   path="[inputs]"          reason=oneOf   val=[{required:[nodes]},...]
no selector at all {through only}    path="[inputs]"          reason=oneOf   val=[{required:[nodes]},...]
bad col inside a good selector       path="[inputs][cols][1]" reason=enum    val=["a","b"]
```

Note the third row: `oneOf` only summarises when the **selector-kind choice itself** is wrong — zero
or two-or-more selectors. A bad *value* inside a well-formed selector still comes back as a leaf
with the allowed columns. And selector-kind is the one error a purpose-built picker can make
unrepresentable by construction (one radio group, not three optional fields), so **§6's picker
design can retire the only leak we have** rather than A7 having to report around it. Worth saying in
A7: the fix for our `oneOf` is a UI affordance, not error plumbing.

*Strengthened by the DashiBoard session on receipt, correctly:* this is now a **requirement** on
§6's picker rather than a property it happens to have. If the picker ever degrades into three
optional fields, the leak returns — and it returns as the one error shape A7 was written not to
handle. Recording the inversion here so the constraint is not lost if §6 and A7 are read apart.

**On `val` as structured data — yes, with one trap.** `val` is a live Julia value, not prose:
`Int64` for a `minimum`, `Vector{String}` for `required`, `Vector{String}` for a column `enum`. But
on a **variant-name** enum failure it is `Base.KeySet{String, OrderedDict{String,Type}}` — a lazy
view over the live `CLUSTERING_METHODS` dictionary, because `match_property("type" => keys(d))`
stores `keys(d)` itself into the schema (`structs/json_schema.jl:169,176`,
`method.jl:39`). It iterates and serialises correctly, but A7 should `collect(String, val)` at the
boundary rather than pass it through: it is a reference into a mutable global, and its type will
surprise anything that pattern-matches on `Vector`.

**On path stability — yes, to three levels.** `"[method][dissimilarity][p]"` is the deepest case in
the card set and converts mechanically to `/method/dissimilarity/p`. One thing A7 must handle: a
`required` failure reports at the **parent** path with the missing name in `val`
(`path="[method]"`, `reason="required"`, `val=["classes"]`), which is correct JSON Schema but means
the pointer alone does not identify the field — the form has to join `path` and `val` to highlight
the right control. That is the one place `related` earns its keep beyond the `weights`/`inputs` pair.

---

## Appendix E — state of this brief

Reconnaissance is closed. Sections 0–9 are the original brief; Appendix D is the correspondence with
the DashiBoard session, all of it executed rather than argued. Every result in D1–D12 has been
re-checked against the **working-tree** Pipelines (D11), so nothing here rests on the resolved
package that §0.3 flagged.

**What is settled and belongs to others:** A1a (the tag-equality gate, D10), A3a (drop the `$ref`
sibling, D4 as corrected by their Ajv measurement), A3b (`MethodSpec`, D2), A3c (`x-dashi-order`,
D1 + D10's plumbing answer), A3d (`$defs` for variants, D3 — the shed candidate), A3e (stop aliasing
the `$ref` pointer constants, D13 — ordered before anything that writes into a served schema, and
pairs with A1a), A7 (leaf errors, D6 + D12). D13 also confirms the type-bound mechanism §3 rests on:
`fieldtype` on the stored `UnionAll` yields the abstract bound as a `DataType`, and dispatch on it
selects the `@options` overload — the only compile-time step in the whole schema path.

**What is mine, in order:** ~~B3~~ **landed at `b2f38c7`** together with `run_id` progress events
and strict parameter checking (Appendix F5) — AgentGraph's probe switch is unblocked. Remaining:
B1 (CORS + `assets`), B2 (group dialect + the `dashi/1` envelope, D7), B4 (the `else` branch,
§8.2). Then B5–B7.

**One decision outstanding, with the project owner:** whether `ExperimentTracking:Project.toml:23-27`
switches Pipelines from the GitHub URL to a dev path. It is item zero of `06-design.md` and it is
needed for *implementation* — it is what makes a Pipelines edit visible to this package's
environment, tests and CI. It is **not** needed for verification: the throwaway scratchpad
environment in D11 rebuilds in about fifteen seconds and pins all five packages to their working
trees without modifying either repository, so any claim in this brief can be re-checked against
shipping code on demand. The two can therefore be sequenced independently.

Implementation has begun on `ds-DashiUI`; first commit `b2f38c7` (Appendix F5). The tree is
clean at that commit.
### D13 — Type bounds, memoisation, and a shared-mutable-state trap that A3c would trip

Four questions from the DashiBoard session about what resolves at compile time versus request time in
the *current* implementation. All measured against the working tree. **Their reading is correct on
every point**, and the check turned up an adjacent hazard that lands squarely on A3c.

**Q1 — `fieldtype` on the stored `UnionAll` returns the bound, not a `TypeVar`.**

```
CARD_SPECS["cluster"].type      = ClusterCard      (isa UnionAll = true)
fieldtype(ClusterCard, :method) = Pipelines.ClusteringMethod
  typeof = DataType   isa TypeVar = false   isabstracttype = true   === ClusteringMethod = true
```

**Q2 — the narrowing bounds come through exactly as expected.**

```
fieldtype(KMeansMethod, :dissimilarity) = DissimilarityMethod
fieldtype(DBSCANMethod, :dissimilarity) = MetricMethod
MetricMethod <: DissimilarityMethod = true
```

**Q3 — yes, dispatch reaches the `@options` overload, and the counts prove it end to end.**

```
which(schema_from_type, Type{ClusteringMethod})     -> Pipelines/src/method.jl:38
which(schema_from_type, Type{DissimilarityMethod})  -> Pipelines/src/method.jl:38
which(schema_from_type, Type{MetricMethod})         -> Pipelines/src/method.jl:38
   (the generic fallback is structs/json_schema.jl:3 — not selected)

composite_schema(KMeansMethod).dissimilarity -> 9 variants
composite_schema(DBSCANMethod).dissimilarity -> 7 variants
```

Same field name, two structs, different option lists, with no declaration anywhere saying so. That
is the whole mechanism `01-decisions.md` §3 relies on, and it works.

> **Correction to the binding document — since applied.** `01-decisions.md` §3 and
> `00-dashiboard-context.md` both said `DBSCANMethod{D <: MetricMethod}` offers "only the **six**
> true metrics". Both now say seven, as does `07-json-schema-and-ui.md:96-97`; this note is kept
> for the reasoning rather than the defect. It is **seven**: `euclidean`, `cityblock`, `chebyshev`, `minkowski`,
> `weighted_euclidean`, `weighted_cityblock`, `weighted_minkowski` — the nine dissimilarities minus
> `sqeuclidean` and `weighted_sqeuclidean`, which are excluded because a squared Euclidean distance
> violates the triangle inequality. Small, but it is a number in the binding spec and it is the kind
> that ends up in UI copy or a test assertion.

**Q4 — nothing is memoised. Every call rebuilds from reflection.**

```
composite_schema twice -> same object? false    equal content? true
card_schema twice      -> same object? false    mutating one affects the other? false
mean card_schema("cluster") = 0.11-0.18 ms      (rebuilt per call)
```

So the reading offered is confirmed: `@options` expands to methods that reference the registry *by
name*, the registries are populated at module load, `CARD_SPECS` is filled in `__init__`
(`DashiBoard:Pipelines/src/Pipelines.jl:197-206` — so genuinely per-session, not baked into the
precompiled image), and the schema is rebuilt by reflection per request. **The only compile-time
step is method dispatch**, and that is precisely what converts an abstract bound into a variant
union.

#### The adjacent hazard: `$defs` sub-dicts alias module constants

Q4's "not memoised" is true of the *top level* but not all the way down. Two independent
`card_schema` calls share object identity at some nested paths, and those shared objects are the
module constants themselves.

In the **group dialect — the one B2 will serve — 24 paths alias three constants**:

```
JSON_NODE   ALIASED at 12 paths  (.../properties/nodes/items, .../properties/through/items, ...)
JSON_GROUP  ALIASED at  6 paths
JSON_COL    ALIASED at  6 paths  (.../properties/cols/items in variable, variables, nonempty_variables)
```

Writing to one is process-global and permanent. VERIFIED:

```
target === JSON_COL ? true
JSON_COL before = {"$ref":"#/$defs/col"}
JSON_COL after  = {"$ref":"#/$defs/col","x-dashi-note":"written by one request"}
GLOBAL CORRUPTED? YES
a FRESH schema for a DIFFERENT pipeline now carries it? YES — leaked across requests
```

(process state restored afterwards).

**Why this matters now rather than in the abstract.** It is latent today — nothing writes into a
served schema. It goes live with **A3c**, whose implementation D10 recommended as "assign
post-construction", and with **§14 rule 1**, whose instruction is literally *"inject into an existing
property dict"*. Top-level property assignment is safe, because `schema_from_type` merges the tag
into a fresh dict (`json_schema.jl:24-32`) — I verified `properties.inputs` is **not** aliased. But
anything at `$defs` depth is not safe, and the aliased objects are the small `{"$ref": ...}` pointer
dicts, which are exactly what someone would reach for to annotate "the column reference". A
well-aimed trap.

The current dynamic-enum injection is safe: `schema_definitions(vc)` builds the `col`/`node`/`group`
enums as fresh dicts via `json_string(enum = ...)`. It is the *pointers to them* that are shared.

**Fix, primary:** stop sharing — have `variable_item_schema` and `schema_definitions` use
`copy(JSON_NODE)` / `copy(JSON_COL)` / `copy(JSON_GROUP)` at their six use sites
(`DashiBoard:Pipelines/src/group_api/schema.jl:15-18`, `structs/card_schema.jl:29-30`), or turn the
four constants into zero-argument functions returning fresh dicts. Near-zero cost. Note this
composes with **D10's fix**: once the tag gate compares `$ref` rather than whole-dict equality,
nothing depends on those constants being singletons any more, so the two changes want to land
together.

**Fix, cheap immediate guard:** `deepcopy` once at the `card_schema` boundary. Measured cost —
0.107 ms → 0.303 ms for the worst card, ~27 ms for a nine-card response. Acceptable for a
per-pipeline-edit request, not free, and strictly worse than not sharing in the first place.
Verified it does break the aliasing (`target === JSON_COL` becomes `false`).

---

## Appendix F — `main` vs `ds/file-mode-and-run-events` as an AgentGraph server, measured

Prompted by the project owner: the live stack shows `dashi` **unreachable**,
`ConnectError: [Errno 111] Connection refused` against `http://127.0.0.1:8081/`, and the working
hypothesis was that `main` cannot serve AgentGraph while the branch can.

**Both halves needed separating.** The refusal is not the compatibility gap, and the compatibility
gap is real but does not point at switching branches. Method: AgentGraph's exact wire payload —
built as `remote_procedure.py` builds it, `dataflow` flattened into `params` — replayed against both
trees. The branch was extracted read-only with `git archive`; neither repository was modified.

### F1 — The connection refusal is a startup crash, not a protocol failure

`agentgraph:start_stack.sh:102-127` writes a launcher to `/tmp/ag-et-serve.jl`, whose line 21 is

```julia
sink = ExperimentTracking.RedisStreamSink(RedisConnection(port = 6379))
```

`RedisStreamSink` exists **only on the branch**
(`ds/file-mode-and-run-events:src/events.jl:106-113`, with the method supplied by
`ext/ExperimentTrackingRedisExt.jl`). The checkout is on `ds-DashiUI`, which is cut from `main` and
has neither. Observed in the `ag-experiment` pane:

```
ERROR: LoadError: UndefVarError: `RedisStreamSink` not defined in `ExperimentTracking`
   @ /tmp/ag-et-serve.jl:21
```

The process exits before `HTTP.serve!` on line 23, so nothing listens on 8081 — confirmed, no
listener on that port and no server process. **Connection refused is the launcher, not the wire.**

Worth stating plainly because it changes what the symptom means: **the health probe would go green
on `main`.** `GET /v1/services/dashi/health` runs `discover()`, which posts `cards`, and `cards`
answers correctly on `main` (measured below). A reachable `dashi` on `main` would therefore look
healthy and still be unusable — which is a worse failure mode than the one being seen now.

### F2 — Once running, `main` genuinely cannot serve AgentGraph

AgentGraph's four wire interactions, replayed against each tree:

| AgentGraph operation | wire method | `main` | branch |
|---|---|---|---|
| `discover()` / health probe | `cards` | **OK** | **OK** |
| `validate_remote()` | `validate` | **-32601 method not found** | OK |
| `call("train")`, file mode with `load_options` | `train` | **-32603 Binder Error** | OK |
| `call("eval")` with `from` | `evaluate` | (blocked by the above) | OK |

On the branch the train call also returned `run_id` in its result and wrote the destination
correctly — 40 rows, `[_part, PRES_rescaled, TEMP_rescaled, No]`.

**The `train` failure is exactly the `load_options` rename**, isolated with three controls on `main`:

```
comma CSV, no options (control)                 OK
semicolon CSV, AgentGraph's `load_options`      FAIL -32603 Binder Error
semicolon CSV, main's `source_options`          OK
```

So `main`'s file mode is healthy; the only defect is the field name. AgentGraph sends `load_options`
at the top level (`agentgraph:src/agentgraph/tools/remote_procedure.py:258-262`); `main` renamed it
to `source_options` and moved it inside `DataFlow` (`ExperimentTracking:src/entries.jl:119`), and
`make` ignores unknown keys, so it is dropped in silence. With `delim` that fails loudly; **with
`nullstr` it would corrupt data silently**, which is the case to worry about.

### F3 — But the branch is not the answer either, and switching to it would cost more than it buys

The branch is three commits ahead and **six behind**. Against `main` it lacks:

- **`api/v1/probe`** — the better answer to "validate without executing" (§6.4), which applies to
  every method rather than one.
- **`source_metadata["cols"]`, and therefore all column validation.** The branch's
  `initialize_pipeline(c::Config) = Pipeline(c.nodes, c.groups)`
  (`ds/file-mode-and-run-events:src/entries.jl:98`) passes no `cols` at all. Every finding in D9 —
  that supplying columns converts ACCEPT into REJECT for card fields and group definitions — is
  main-only. `01-decisions.md` §2's whole save-annotation story rests on it.
- **`source_options` / `destination_options`** as `DataFlow` fields.
- **A registry migration in the wrong direction.** `DATA_FLOW_COLUMNS` is nine columns on `main`
  (`ExperimentTracking:src/schema.jl:36-46`) and **five** on the branch. `initialize_registry_table`
  builds `CREATE TABLE` from `ENTRY_COLUMNS` and `row2entry` reads by those names, so a registry
  written by one tree is not readable by the other. Switching branches is a schema change, not a
  checkout.

### F4 — Recommendation: port the branch's three capabilities onto `main`

Not a merge, and not a switch. Three targeted changes, all small, all already in the plan or
adjacent to it:

1. **Make the probe return the analysis** — `{valid, source_vars, output_vars}` instead of `null`.
   This is **B3**, already sequenced, and it is what lets AgentGraph retire `validate` in favour of
   the probe route (which that session has already agreed to). Until it lands, AgentGraph's
   `dashiboard_validate` tool is dead against `main`.
2. **Accept `load_options` as a deprecated alias for `source_options`** — one line in
   `execute_handler`. Worth doing on this side even though AgentGraph should also rename, because
   ET is the shared service and a silent drop is the worst available behaviour. Pair it with an
   explicit error on unknown top-level params, so the next rename fails loudly instead.
3. **Port `run_id` progress** (`ds/file-mode-and-run-events:src/events.jl`) when progress is wanted.
   Not blocking: `run_id` being dropped costs correlation, not correctness. Its design is sound —
   opt-in, callbacks wrapped rather than replaced, emission shielded so a dead transport cannot fail
   a good run, transport behind a package extension.

### F5 — Landed: `ds-DashiUI` at `b2f38c7`

The project owner chose to port onto `ds-DashiUI` (to merge into `main` later) and to keep the API
**strict** — no `load_options` alias; consumers are taught the new vocabulary. Done under TDD; every
test below was watched to fail first. Full suite green, and the real `agentgraph` launcher
(`/tmp/ag-et-serve.jl`, unmodified) now starts against this tree and answers.

**What changed on the wire, for every consumer:**

| | before `b2f38c7` | after |
|---|---|---|
| `POST api/v1/probe` on `train`/`evaluate` | `result: null` | `{valid, source_vars, output_vars}` |
| unknown top-level param (e.g. `load_options`) | silently dropped | **`-32602`** naming the key and the accepted set |
| `run_id` | silently dropped | accepted; opts into progress events; **echoed in the result** |
| `validate` method | absent | **still absent — deliberate.** Use the probe route. |
| `get_router(...; sink)` | no such kwarg | installs a progress sink; `RedisStreamSink` via the `Redis` extension |

Accepted `train`/`evaluate` params, exhaustively: `database, destination, destination_options,
file_based, filters, from, groups, id_var, nodes, run_id, schema, source, source_metadata,
source_options`. Anything else is refused. **AgentGraph's side is done** (session `agentgraph-64`,
uncommitted pending another session's hold on their shared checkout): `load_options` →
`source_options` at `agentgraph:src/agentgraph/tools/remote_procedure.py:258-262`;
`validate_remote()` → `api/v1/probe` with method `"evaluate"`; the `run_id` field description
corrected (it reached the designer LLM via generated tool docstrings); "`valid` is only ever true,
branch on `error`" and "a bogus `from` passes the probe" recorded in their wire notes. Verified by
them against the live server on `127.0.0.1:8081` running `b2f38c7`; their
`tests/integration/test_live_dashiboard.py` passes, `dashiboard_validate` included.

Measured over the wire, launcher-served:

```
cards            -> OK, 9 card types
probe train      -> {"valid": true, "source_vars": ["cbwd","No","PRES","TEMP"],
                     "output_vars": ["_tiled_partition","PRES_rescaled","TEMP_rescaled"]}
legacy load_opts -> -32602 | Unknown parameter(s): load_options. Accepted parameters: database, ...
```

**Probe contract, three nuances verified over HTTP for the AgentGraph session** (they go into
`remote_procedure.py`, so they are observed, not read):

- The probe is JSON-RPC-enveloped like `api/v1`; `method` is `"train"` or `"evaluate"` — the one
  whose validation you want. Bare params → `-32600`; `"validate"` → `-32601` on both routes.
- **A bogus `from` passes the probe** (`from = 999`, no such run → `valid: true`). The registry
  lookup for `from` is in the execution phase, not validation, so the probe confirms the payload
  and pipeline are well-formed but does **not** confirm a warm-start run exists. AgentGraph's
  preflight remains the only check on that.
- `valid` is always `true` when present; rejection arrives as `error`, never `valid: false`.
  `run_id` is echoed in the real route's result and is **not persisted** to the registry — it is
  the progress-stream key only. AgentGraph's field description ("recorded on the DashiBoard run;
  auto-assigned when omitted") is wrong on both counts and has been flagged to them.

**Design note worth keeping.** The `run_id` wrapping lives *inside* `ExecuteThunk`
(`ExperimentTracking:src/api/handlers.jl`), not around it, so `probe_result` still dispatches on an
`ExecuteThunk` and the probe keeps returning the analysis for `run_id`-bearing requests — and never
emits, because emission is in the thunk the probe discards. Asserted in `test/events.jl`.

**Not done, deliberately:** B4 (the external-database `else`, §8.2) is not a port and was not asked
for; still one line, still open. `scripts/server.jl` still uses its own manual Redis callbacks — it
keeps working because the wrappers call the previous callback first.
