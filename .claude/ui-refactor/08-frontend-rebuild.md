# 08 — The frontend rebuild: what to build on, and in what order

Written for the team leader, who owns `origin/pv/frontend`. `01-decisions.md` stays binding; this
file does not contradict it. It exists because §7 committed to a rebuild before the IR existed and
before the other three repositories had been asked anything, and both of those have now changed.

Reading order: `01` §§7, 9–11, 13, then this, then `06-design.md` Track C.

---

## 1. The recommendation in one line

**Rebuild the program on `dashiboard-ui`'s foundation. Do not port `frontend/`, and do not start a
third app.** The toolchain is right; the application layer is a template.

Everything below is either evidence for that or a consequence of it.

## 2. Why not a port

§7 already settled it — "the whole frontend is rebuilt", the canvas replaces the left tabs entirely,
and the result panes are "rebuilt rather than ported", retiring `frontend/src/left-tabs/`,
`right-tabs/` and `filters/`. Measured against that, a port is costing work the specification
deletes: of the 664 unported lines in `frontend/src`, §7 retires 226 outright (`left-tabs` 163,
`right-tabs` 63) and `cards/auto-widget.jsx` (95) is what C1 replaces with the IR renderer. What
would remain to transcribe is close to nothing.

One correction to an impression that may be circulating: the DAG canvas is **not** a hard piece.
`frontend/src/right-tabs/graph.jsx` is 19 lines — `@viz-js/viz` does the work. Adding that one
dependency is the whole cost, and it is currently absent from `dashiboard-ui/package.json`.

## 3. What `dashiboard-ui` gets right, and should keep

- **The stack.** SolidJS 2.0.0-rc.4, TypeScript, Vite 8, Tailwind 4. The framework question is now
  closed in SolidJS's favour — see §5 below.
- **Static prerender to `dist/client`** with zero server dependencies. This fits §10 exactly:
  ExperimentTracking serves the bundle, so the app and the API share an origin by construction.
- **`createRoot` stores in `src/root.ts`** rather than context plumbing. Right instinct — the stores
  live outside the component tree, so they survive an embed shell and are reachable from a
  `postMessage` handler.
- **The test setup** — vitest, `@solidjs/testing-library`, and `@solidjs/diagnostics` rerun budgets,
  documented in `dashiboard-ui/AGENTS.md`. This is the only test infrastructure either app has.
- **The ported leaf widgets** — `Combobox`, `TableView`, `Button`, `Input`, `Toggler`, `JSON`,
  `FilePicker`. These are what the IR renderer dispatches *to*, and they are the part porting has
  genuinely bought.

**On `choices.js`:** keep it. Kobalte's published peer dependency is `solid-js: ^1.9.8` as of
0.13.14, so the caret excludes Solid 2; Ark UI declares `>=1.6.0`, which admits 2.0.0-rc.4 by semver
but proves nothing about Solid 2's reactivity changes. `choices.js` has no peer dependencies at all
and one runtime dependency, so it is structurally immune to the Solid 1→2 break. That is a better
reason for the choice than it may have been given.

## 4. What must change, with evidence

**4a. The API base address.** `dashiboard-ui/src/requests.ts:1` does
`import { host, port } from "./request.json"`, and `getURL` builds `"http://" + host + ":" + port`.
That is three violations of §11/C6 in one line: a build-time constant, an absolute URL, and a
hardcoded scheme. It is also factually wrong — `request.json` says `127.0.0.1:8080`, while
ExperimentTracking reports the agentgraph stack runs it on **8081** and DashiBoard's own server also
defaults to 8080. Replace with one `apiBase()` resolving at runtime: postMessage value, else an
injected global or `<meta>`, else same-origin relative. §11 calls this out as the one thing "cheap
now and expensive to retrofit".

**4b. The document must be the model.** §2 is emphatic that round-tripping is "the stored JSON, never
a reconstruction from `Card` objects". `dashiboard-ui/src/root.ts:26-28` has
`cards: {[key: string]: any}[]` — a widget-value bag, which is exactly the shape §2 forbids. The
canonical state must be the authored `Config` `{filters, nodes, groups}`, with widgets as views over
it. This is the most expensive item to retrofit, because it changes every component's read and write
path. Do it first or accept doing it twice.

ExperimentTracking confirms the mechanism underneath already satisfies §2: `row2entry` does
`make(Config, row2dict(...))` with `from_json` on the three JSON columns, so no `Card` is
constructed on that path. One caveat they flagged — storage canonicalises key order
(`to_json` with `sort_keys = true`), deliberately, because it is what makes "have I run this config
before?" answerable by JSON equality. Content round-trips exactly; authored key order does not.
**Treat the stored form as canonical rather than trying to preserve ordering.**

**4c. One recursive renderer, not per-kind panels.** §13 gives the frontend two artefacts: validate
with the JSON Schema, render from the IR. So the program is a recursive dispatch over a closed set of
IR node types, plus a separate validation pass attaching errors by JSON Pointer (A7). The
hand-written `IntervalFilter`/`ListFilter` panels are the opposite architecture — and §7 folds
filters into the canvas regardless.

**4d. The shell must be dual.** `dashiboard-ui/src/App.tsx:14-21` hardcodes a `<nav>` with a "Home"
link into the root. The app has to work in two shells — standalone with chrome, embedded with none
and host-controlled sizing. Cheap to design in; unpicking a global layout later is not.

## 5. What has been settled since `06-design.md` was written

- **The IR landed** — `DashiBase/src/IR.jl`, on `main` as of `3e7c2e5`/`cd2e88b`/`66bdff2`. The
  "Decisions needed" row gating A3 "and therefore everything" is closed.
- **`Pipelines.card_ir` and `ir_definitions` now exist** and are declared `public`
  (`Pipelines/src/card_schema.jl`), with `card_schema` reduced to `json_schema(card_ir(key))` plus
  the type discriminator. Output is byte-identical — 630 assertions pass. **What still does not
  exist is a route serving the IR**; ExperimentTracking has offered to add the wire method now that
  the names are public.
- **A3a is resolved** — the `$ref`-sibling defect went with the IR rewrite. See `06-design.md`.
- **The framework question is closed.** §12's node inspector is ruled out. nexus-weaver-pro's
  argument is structural: `ChatWidget` builds its context from router state, a static per-route
  string and app-level globals, and its `useMemo` dependency array carries no page component state
  for any page (`nexus-weaver-pro:src/components/ChatWidget.tsx:225-228`). No mechanism exists by
  which a page publishes state to that widget.
- **The embed contract is far thinner than C5 implied**, and the theming contract is settled. See
  `06-design.md` → *C5 in detail*.
- **ExperimentTracking's side is less built than §10 implies.** Its router registers two routes, both
  POST (`api/v1`, `api/v1/probe`). There is no static-asset serving, no CORS of any kind — not merely
  a missing header but no `OPTIONS` route — and **no Config save/load on the wire at all**: the four
  methods are `train`, `evaluate`, `cards`, `schema`, and the registry is written as a side effect of
  runs and never read back over HTTP. That is B1 and B6, both unstarted.

## 6. The critical path: the standalone UI depends on nothing outside this repository

**Scope decision, 2026-09-09.** The work is to complete the standalone `dashiboard-ui` all the way
down, and then hold for the team leader's review of DashiBoard and ExperimentTracking. Everything else
in this section is a separate track and must not be allowed to set the order.

`DashiBoard` depends on neither `ExperimentTracking` nor `AgentGraph` — checked, no reference in
`DashiBoard/src/` or `DashiBoard/Project.toml`. The package arrows run the other way: AgentGraph
consumes ExperimentTracking, which consumes Pipelines. So the standalone UI is downstream of nothing,
and **§9's layering is also the dependency order**: layer 1 (standalone) needs only this repository;
layers 2 (registry, lineage) and 3 (the embed) are what involve the others.

Concretely, every endpoint layer 1 needs already exists or is ours to add:

| the UI needs | served by | status |
|---|---|---|
| the card IR | *a new DashiBoard route* over `Pipelines.card_ir` / `ir_definitions` | **ours to add — the one gap** |
| card widgets (until the renderer replaces them) | `POST /get-card-widgets` | exists |
| source selection, load, column summaries | `/get-acceptable-paths`, `/load-files` | exists; `summarize` already returns `{min,max}` and unique values, i.e. the two filter shapes |
| pipeline run, results, DAG | `POST /evaluate-pipeline` | exists — returns `summaries, visualization, graph, report` |
| paged data | `/fetch-data`, `/get-processed-data` | exists |
| CORS for a Vite dev server | `DashiBoard/src/middleware.jl:1-7` | exists, unconditional `*` |

So the earlier framing — that ExperimentTracking's B1 "gates all frontend work" — was true only of
work *against ExperimentTracking*, and that work is layer 2. **Nothing is waiting on AgentGraph at
all**, in either direction.

What ExperimentTracking's B1 and B6 do gate is the *hosted* story: serving the bundle same-origin, and
saving a `Config` to the registry. Those are layer 2, they come after the review gate, and the runtime
`apiBase()` of §4a is what keeps them from becoming schedule coupling — the same bundle points at
DashiBoard:8080 today and ExperimentTracking later, by configuration.

**The wire-format break travels with this branch, deliberately.** `9bd6c28` — "avoid auto conversion
from list to scalar" — is a public wire-format break, and it is in `ds-DashiUI`'s ancestry via the
`origin/main` merge at `d1a9505`. ExperimentTracking's `main` is pinned to `66bdff2` to avoid it, and
cutting a `card_ir`-only branch from that pin was considered and **declined by the project owner**:
all adaptation for this effort lives on the `ds-DashiUI` twin branches in all four repositories, not
on side branches. Recorded so nobody re-proposes it.

What that decides, per repository:

- **DashiBoard `ds-DashiUI`** carries both the break and `card_ir`. Done — `073ece6`.
- **ExperimentTracking `ds-DashiUI`** points its `[sources]` at DashiBoard's `ds-DashiUI` and adapts
  to the new format there, whenever it suits that track. **Its PR #24 to `main` is not to be merged**
  (owner, 2026-09-09), so the branch is a staging area rather than a merge vehicle and adopting the
  break carries it nowhere. The earlier merge-first sequencing is void.
- **AgentGraph `ds-DashiUI`** sends the new shape and owns five in-repo call sites. Not on the
  standalone path, and not waiting on us — nor us on it.

**The residue a branch strategy cannot solve, and the real gate on merging to main:** `Config`
documents already persisted in ExperimentTracking's registry and in AgentGraph's artifact store are
in the old format. That is data, not code — no feature branch adapts it, and **nothing in this plan
currently owns the question.**

*What the break actually is*, read off `9bd6c28`'s diff to `group_api/schema.jl` — it is narrower
than "the group format changed", and the shape matters for any migration:

| | before `9bd6c28` | after |
|---|---|---|
| plural field (`VARIABLES_DEF`) | object **or** array of selectors | **array only** |
| singular field (`VARIABLE_DEF`) | object **or** 1-element array | **object only** |
| selector value (`cols`/`nodes`/`groups`) | array of strings only | **string or array** |

So the one-or-many moved *inward*: it used to sit at the field level (`one_or_many_schema`), and now
sits at the selector-value level (`OneOrManyIR`). Three consequences:

- **The inner change is backward-compatible.** Every old selector value was an array, and arrays are
  still accepted. Nothing needs migrating inward.
- **The field level breaks in *opposite directions*.** A plural field stored as an object must be
  wrapped; a singular field stored as a 1-element array must be unwrapped.
- **Therefore shape-sniffing cannot work at all** — not "is fiddly". Demonstrated by the
  ExperimentTracking session, building real pipelines through `initialize_pipeline` against current
  upstream:

  | stored shape | as a plural field | as a singular field |
  |---|---|---|
  | `{groups = "w"}` (object) | **rejected** | accepted |
  | `[{groups = "w"}]` (array) | accepted | **rejected** |

  The same two shapes have *opposite* validity by arity. So the shape carries no information without
  the field's arity, and the document never records it — only the card's schema does. **A read-time
  migration must walk each document against the card IR**, per card type. It is not a context-free
  transform, which is how it will be attempted if nobody writes this down.
- **There is no second failure mode at construction.** The obvious worry — schema-valid but failing
  later when a 1-element `Vector` meets a `String` field — was tested and does not occur; `9bd6c28`
  also touched `group_api/deps.jl`. One validation check per document is sufficient.

*Therefore:* **record a format version on stored `Config` documents**, before more are written rather
than after. `CONFIG_COLUMNS` is `filters`, `nodes`, `groups` and nothing else, so a reader cannot ask a
stored document which vocabulary it was written in — a `version` key was recommended in
`04-experimenttracking-brief.md` before any of this arose, on the grounds that the document was about
to start being saved, imported and round-tripped. This is that moment.

But be clear what it buys, because it is narrower than it looks: **a version cannot help the
transform**, which needs each field's arity from the card IR either way. What it buys is knowing
*whether* a document needs walking at all. Without one you must attempt the walk on every stored
document and rely on it being a no-op for already-migrated ones — which it is, given correct arity,
and "correct" is doing real work in that sentence.

**And one class cannot be migrated at all, with or without a version.** A `WildCard`'s field vocabulary
comes from `WildCardSettings` at registration, not from a fixed struct: `WildCardIR`
(`Pipelines/src/cards/wild.jl:89-122`) adds `weights` and `partition` as **singular** `VARIABLE_DEF`
properties only when `allows_weights` / `allows_partition` are set. So whether a stored wild-card
document even *has* a singular field depends on how its type was registered — and `get_spec` throws
on an unregistered key. **A stored document whose card type is not currently registered has no
derivable arity and cannot be migrated.** This is not theoretical: `card_ir("trivial")` fails exactly
this way until `register_wild_card` has run, which is how the test harness for `card_ir` first broke.

*Sized, and the answer closes it:* **there is no stored-data gate. This is a changelog paragraph, not
a backfill, and it needs no owner.** The AgentGraph session queried its live Postgres artifact registry
rather than estimating: of 87 rows, exactly **two** are pipeline `Config`s —
`dashiboard-simple-pipeline` @1.0.0 and @1.0.1, both written on 2026-09-03 within 300 ms of each other
by `init_dashiboard_resources` installing the two demos. And both were registered with `register_file`
*in place*, so their `path` dereferences to one file checked into the AgentGraph repo
(`configs/dashiboard/pipeline.toml`) with no copy under `ARTIFACT_ROOT`. **Editing that one file
migrates both versions.** There is no stored content to rewrite. Two lineage refs pin those versions
and stay resolvable, because the same single file sits behind them.

Scope of that answer: the local dev registry. CI brings up a fresh Postgres per run, no other
deployment holds an artifact store, and Dolt is clean — of 60 `graph_versions`, the four mentioning
dashiboard declare `groups` as an input *name* plus a `registry_key`, embedding no card values in
either shape.

The version key remains worth adding for the reasons above, but it is now hygiene for documents not yet
written rather than a prerequisite for anything. Stored configs *are* replayed through validation
(`ExperimentTracking:test/interface.jl:69` calls `initialize_pipeline` on a config read back out of the
registry), so the path is exercised — there is simply almost nothing on it.

**What the break does cost is code, and one item is a new silent failure worth naming.** AgentGraph
owns five in-repo call sites and has accepted them; four break loudly and are therefore fine. The fifth
does not:

**`_dashi_preflight` fails open** (`agentgraph:src/agentgraph/tools/platform/dashiboard.py:68`). It
walks `kw["groups"].items()` and guards with `if isinstance(group, dict)`. After the break a group
definition is a **list**, the guard is False, and the loop silently checks nothing — no crash, no
finding. Ghost column references stop being caught client-side and resurface later as SQL errors.

That matters here beyond AgentGraph's own repo because it is the third leg of the systemic finding in
`06-design.md` Track D: three mechanisms were each meant to catch a card referencing a nonexistent
column, and all three are already broken or absent. This break converts the last one from *partial* to
*silently inert*. It reinforces rather than softens §2's rule that the UI must always send `cols` —
currently the only such mechanism that would work at all.

One related confirmation, from the same query: **nothing persists a node→pipeline link.**
`RichNode.dashiboardPipelineId` exists only as mock UI state, and `linkPipelineToNode` PUTs
`/graphs/{id}/nodes/{nodeId}/dashiboard`, a route absent from AgentGraph's API. So C5's thin boundary
is thinner still — there is no stored relationship for an embed to read or write yet.

**Two verified facts worth keeping even though the branch was declined.** First, `card_ir` does not
depend on the break — `Pipelines/src/card_schema.jl` is byte-identical at `66bdff2` and at this
branch's HEAD, and every name it references resolves at that pin. So the IR work and the format
migration can be reasoned about, reviewed and reverted independently even while sharing a branch.
Second, and load-bearing for B2: **`ObjectIR`'s `constraints::Vector{StringDict}` field is already
present at `66bdff2`** (it came with `cd2e88b`), yet `variable_item_schema` there does not use it —
it builds `ObjectIR(; properties)`, converts with `json_schema`, then assigns
`schema["oneOf"] = [...]` onto the result. That is a live instance of *Do not annotate a built
schema*, and it makes the selector-kind constraint invisible in the IR. Current `main` fixed it by
passing `constraints = [Dict("oneOf" => oneOf)]` into the `ObjectIR` (`variable_item_IR()`). The
lesson generalises past the pin: **whenever the group dialect is served, check that its `oneOf` is
inside the IR and not bolted onto the schema**, because §6's variable picker — C2's dependency — is
exactly what that constraint governs, and A7 cannot attach an error to a constraint the IR does not
describe.

## 7. Order

1. **Runtime `apiBase()`**; delete `request.json`. Unblocks everything else and costs an afternoon.
2. **Document-as-model store.** Replace `cards: any[]` with the authored `Config`. Most expensive to
   defer.
3. **Recursive IR renderer + validation overlay.** Buildable now against a hand-made IR fixture from
   `Pipelines.card_ir` output; switch to the served IR when the route exists.
4. **Dual shell** — `/` with chrome, `/embed` without, `?theme=` read once, tokens by `postMessage`.
5. **Canvas** (C3) — add `@viz-js/viz`; and the result panes, rebuilt per §7.
6. **Delete `frontend/`.** Then the DashiBoard server once the new UI serves, per *Do not do*.

`frontend/src/create.js` is currently deleted by `pv/frontend` while eight modules still import it,
so `frontend/` does not build (`Could not resolve "./create" from "src/App.jsx"`). Under this plan
that is coherent — it is deleted rather than repaired — but the half-state should not persist.

## 8. Open, and whose

| Question | Owner |
|---|---|
| Where a per-deployment palette comes from. §11 requires runtime for DashiBoard regardless; the open part is whether nexus-weaver-pro adopts the same rule | project owner, both repos at once |
| Visualization: server-rendered Makie SVG or client-side? Gates retiring the DashiBoard server, nothing earlier | project owner |
| Filter annotations in DataIngestion or Pipelines (A6) | project owner |
| `$defs`+`$ref` for a composition-free client validation entry point | defer until A7's error quality is measured |

## 9. Two IR defects the renderer will meet

Both found by execution, neither reachable from any TOML today, both recorded in `06-design.md`:
`IR_DICT` maps `"boolean" => IntegerIR` (`DashiBase/src/IR.jl:172`), so `{"type":"boolean"}`
deserialises to `NumericIR{Int64}`; and `NumericIR`'s four bound fields are typed `Maybe{Int}` while
`default`/`enum` use `T`, so `NumberIR(minimum = 0.5)` throws `InexactError`. The second will bite
the first time a card wants a fractional bound — `PercentileMethod` only works today because its
bounds are `0` and `1`.

## 10. Do not

- Do not port `left-tabs/`, `right-tabs/` or `filters/`. §7 retires them.
- Do not port `cards/auto-widget.jsx`. C1 replaces it.
- Do not scope a rich `postMessage` contract. The counterparty does not exist yet.
- Do not bake a host, port, scheme or palette into the bundle. §11.
- Do not reintroduce a sibling beside a `$ref` when A3b adds variant labels. See A3a.
