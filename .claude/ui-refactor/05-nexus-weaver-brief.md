# 05 — nexus-weaver-pro reconnaissance brief

Written by the nexus-weaver-pro session. Repository:
`/home/dariosarra/Documents/Limen/nexus-weaver-pro`, branch `ds-DashiUI`, cut with
`--no-track` from `main` at `7c578e6` (tree was clean, pull was already up to date).

Reconnaissance was read-only: nothing in this repository was modified. Every claim below
cites `nexus-weaver-pro:path:LINE`. Anything not read directly from source is prefixed
`INFERRED:`.

> ## ⚠ Line numbers are against `7c578e6` (2026-08-28). The branch has since moved.
>
> `ds-DashiUI` was reset to `origin/main` on 2026-09-09 and now sits at `347f7f0` — 52 commits
> on, including the Live Test work (#10–#14). **Every citation below was correct when written
> and several no longer resolve at HEAD.** Two sessions have now read this as a reference, and
> one landed in the wrong block, so the drift is measured rather than left to be rediscovered:
>
> | Cited file | at `7c578e6` | at `347f7f0` | |
> |---|---|---|---|
> | `NodeEditorDialog.tsx` | 615 | 962 | **+347** — substantially rewritten |
> | `api.ts` | 2889 | 3152 | **+263** — e.g. `servicesApi` 978 → **1035** |
> | `artifactFacts.ts` | 430 | 366 | **−64** — one export removed |
> | `ChatWidget.tsx` | 712 | 730 | +18 |
> | `GraphBuilderPage.tsx` | 1635 | 1652 | +17 — e.g. `"pipe-1"` 436 → **453** |
> | `DashiboardPage.tsx`, `ConnectionPanel.tsx`, `artifacts.ts`, `AppLayout.tsx`, `index.css`, `tailwind.config.ts`, `GraphMinimap.tsx`, `toolRegistry.ts`, `RegisterArtifactDialog.tsx` | | | unchanged |
>
> **Reading at HEAD: locate by symbol, not by line.** The claims are anchored to named
> functions and constants, which is what makes them re-findable — `grep -n "servicesApi"`,
> not `sed -n '978p'`.
>
> **Every load-bearing claim was re-verified at `347f7f0` on 2026-09-09 and all of them hold**,
> including in the two files that changed most: `PROVIDERS` (:110), `paramInput` (:121) and
> `buildFromSuggestions` (:92) survive in `NodeEditorDialog.tsx`; `pipelineFitsTable` (:292)
> and `missingColumns` (:302) survive in `artifactFacts.ts`; `inferKind` (:54) and the
> 15-entry-fallback post-mortem (:5) are untouched in `toolRegistry.ts`. Sections 4 and 5 also
> survive #13's "Friendly form over the graph's schema": that form reads a flat
> `LiveTestInputField {name, type?, required?, default?}` list from graph YAML
> (`useLiveTest.ts:19-26`), not JSON Schema, and `editorKind`
> (`LiveTestInputsForm.tsx:76-82`) maps a type *string* to one of four widgets with `json`
> falling back to a textarea. `GET /v1/graphs/schema` remains unconsumed and `zod` still has
> zero imports — a third instance of the pattern §4c documents, not a refutation of it.

> **Amended after `01-decisions.md` gained §13 and the reconnaissance findings in §2, §3, §4
> and §10.** Four corrections, marked **[amended]** at the point of change: the save handshake
> (§8g) now accounts for there being no HTTP route that writes `content_metadata`, and for
> `required_columns` not being `source_vars`; the schema profile (§9) gains a map node for
> §4's free-form `groups` shape; and the positional-order claim in §9 is withdrawn, because
> §3 is right that an order constraint cannot demote to a validation error. Nothing else
> changed. Two of these were places where this brief contradicted the binding spec, and in
> both the spec was correct.

---

## Summary — the six things worth knowing before designing

1. **The placeholder is not a specification, and it never was one.** `DashiboardPage.tsx`
   makes zero network calls, imports nothing from `src/lib/api.ts`, and has not been touched
   since 2026-05-06 while the artifacts, services and benchmarks surfaces were built around
   it. Its data model is invented whole. Section 1 separates the four affordances that carry
   real design intent from the rest.

2. **I recommend the iframe, and I understand that this frees DashiBoard's framework.**
   The decisive argument is not cost — it is that a React-component embed forces this app's
   *only* privileged relationship with the Julia side to be a compile-time one, and section 7
   shows that relationship is already runtime, already user-editable, and already shipped.
   Section 2 has the full enumeration.

3. **There is no form layer to reuse.** `zod` is in `package.json` and imported zero times in
   `src/`. `@hookform/resolvers` likewise. `react-hook-form` is imported only by the vendored
   shadcn primitive `components/ui/form.tsx`, which nothing imports. There is no
   JSON-Schema-to-anything layer, and `GET /v1/graphs/schema` is not consumed. Section 4.

4. **This app independently reinvented the two anti-patterns decision §3 removes**, and has
   already been burned by one of them. `toolRegistry.ts` infers widget kind from parameter
   *name* heuristics because the backend sends names only, and its header documents how a
   client-side fallback catalogue silently became the catalogue for the whole UI. This is the
   strongest in-repo evidence for server-side derivation. Section 4.

5. **`layer` is not the enemy the launch prompt takes it for.** In `GraphBuilderPage` the
   `layer` field is the *output* of Kahn's topological BFS over inferred edges — it is
   derived, never stored, and it is exactly the automatic layout decision §5 asks for. Only
   `DashiboardPage`'s draggable, user-assigned `layer` is filler. Section 6 draws the line.

6. **Two concrete blockers in this repository must be fixed regardless of embedding
   mechanism.** Registering a *new version* of an existing artifact is unreachable from the
   UI by any route — the one operation an iterative authoring tool cannot do without. And the
   Vite dev server occupies port 8080, the default port of both Julia servers, a collision
   the app already warns about in its own error text. Sections 8 and 7.

---

## 1. What the placeholder commits you to

`src/pages/DashiboardPage.tsx` is 822 lines, routed at `/dashiboard`
([App.tsx:45](src/App.tsx#L45)) and listed in the sidebar
([AppSidebar.tsx:31](src/components/AppSidebar.tsx#L31)).

**It is inert.** It imports no API client — the import block
([DashiboardPage.tsx:1-20](src/pages/DashiboardPage.tsx#L1-L20)) pulls only React, lucide
icons, shadcn primitives and `GraphMinimap`. It has no `react-router` import at all, so it
cannot read a query parameter. All state is 12 `useState` calls and one `useRef`
([:233-247](src/pages/DashiboardPage.tsx#L233-L247)). Nothing persists; a reload restores the
samples. `git log` shows three commits, all Lovable-generated "Changes" — two on
2026-04-15 and the last on 2026-05-06.

The repository's own documentation already classifies it: *"Audit, Prompt Editor, Dashiboard,
Profile — demo-data surfaces not yet wired to the backend"*
([docs/frontend-overview.md:113](docs/frontend-overview.md#L113)).

### 1a. The invented data model

| Construct | Lines | Verdict |
|---|---|---|
| `PipelineNode` — `{id,label,type,description,config,layer}` | [:40-47](src/pages/DashiboardPage.tsx#L40-L47) | **Discard.** No counterpart. A Pipelines node has `id`, a `card`, and `inputs` naming variables; it has no free-text `config` blob and no `layer`. |
| `PipelineConnection` — `{id,from,to,conditions}` | [:49-54](src/pages/DashiboardPage.tsx#L49-L54) | **Discard, emphatically.** Edges are inferred (`Pipelines/src/dag.jl:30-56`), and `conditions` is AgentGraph's *router* concept leaking onto a DashiBoard page. Two different graphs got conflated here — precisely what decision §9 forbids. |
| `NodeResult` — `{nodeId,stats,chartData,status,logs}` | [:56-62](src/pages/DashiboardPage.tsx#L56-L62) | **Shape is filler; the three-way split is intent.** See 1c. |
| `Pipeline` — `{id,name,description,nodes,connections,status,createdAt,isToolEnabled}` | [:64-73](src/pages/DashiboardPage.tsx#L64-L73) | **Mostly discard.** `isToolEnabled` is the exception — see 1c. |
| `NODE_TYPES` — 7 emoji-labelled kinds: `source\|filter\|transform\|model\|metric\|visualization\|export` | [:79-87](src/pages/DashiboardPage.tsx#L79-L87) | **Discard.** DashiBoard's card types come from `CARD_SPECS`, served by ExperimentTracking's `cards` method. A hardcoded client-side list of node types is the same mistake `toolRegistry.ts` documents (section 4). |
| `typeColors` | [:89-97](src/pages/DashiboardPage.tsx#L89-L97) | **Discard the mapping, keep the idiom.** It colours by type using design tokens (`border-primary/30`, `bg-info/5`) rather than hex — the correct convention (contrast `GraphMinimap`, section 3). |
| `DEFAULT_CONFIGS` — YAML strings per type | [:99-107](src/pages/DashiboardPage.tsx#L99-L107) | **Discard.** Defaults come from `fielddefaults` on the Julia struct. |
| `SAMPLE_PIPELINES`, `SAMPLE_RESULTS`, `TEMPLATES` | [:109-159](src/pages/DashiboardPage.tsx#L109-L159), [:161-216](src/pages/DashiboardPage.tsx#L161-L216), [:222-226](src/pages/DashiboardPage.tsx#L222-L226) | **Filler.** |

### 1b. Affordances to discard

- **Connection drawing.** `connectFrom` state ([:237](src/pages/DashiboardPage.tsx#L237)),
  "Connect To…" menu item ([:591-593](src/pages/DashiboardPage.tsx#L591-L593)),
  `addConnection` ([:291-296](src/pages/DashiboardPage.tsx#L291-L296)), `deleteConnection`
  ([:298-300](src/pages/DashiboardPage.tsx#L298-L300)), and the per-edge row
  ([:642-666](src/pages/DashiboardPage.tsx#L642-L666)). A user can never draw a DashiBoard
  edge.
- **Routing conditions.** `condDialog`/`condInput` state
  ([:238-239](src/pages/DashiboardPage.tsx#L238-L239)), `addCondition`/`removeCondition`
  ([:302-324](src/pages/DashiboardPage.tsx#L302-L324)), the dialog
  ([:723-743](src/pages/DashiboardPage.tsx#L723-L743)) with its `accuracy > 0.8` placeholder
  ([:738](src/pages/DashiboardPage.tsx#L738)). No counterpart anywhere in the stack.
- **Drag-to-reassign-layer.** `dragId` ([:244](src/pages/DashiboardPage.tsx#L244)),
  `onDragOver` ([:327-330](src/pages/DashiboardPage.tsx#L327-L330)), the drop handler
  ([:549](src/pages/DashiboardPage.tsx#L549)) and `draggable` cards
  ([:558-560](src/pages/DashiboardPage.tsx#L558-L560)). Decision §5 stores no positions.
- **The execution simulation.** `runPipeline`
  ([:343-382](src/pages/DashiboardPage.tsx#L343-L382)) walks layers with
  `setTimeout(800 + Math.random()*600)` ([:365](src/pages/DashiboardPage.tsx#L365)) and
  fabricates an 8 % failure rate: `const hasError = Math.random() < 0.08`
  ([:367](src/pages/DashiboardPage.tsx#L367)). Per-node durations are invented too
  ([:375](src/pages/DashiboardPage.tsx#L375)). All of it goes.
- **`GraphMinimap`** ([:692-696](src/pages/DashiboardPage.tsx#L692-L696)), fed a `type`
  coerced to `agent`/`processor` ([:449-454](src/pages/DashiboardPage.tsx#L449-L454)) — it
  does not even model DashiBoard's own node types. Discard for this page.
- **Dead code:** `stopRef2` ([:255](src/pages/DashiboardPage.tsx#L255)) is assigned and never
  read; `stopRef` ([:247](src/pages/DashiboardPage.tsx#L247)) is set but nothing ever sets it
  `true`, so the `if (stopRef.current) break`
  ([:354](src/pages/DashiboardPage.tsx#L354)) is unreachable — there is no Stop button.

### 1c. Design intent the real UI should honour

Four things here are *not* filler. They are the host's genuine expectations, and each has a
real counterpart in the refactored stack.

1. **A document switcher, and more than one document.** The header `Select`
   ([:472-486](src/pages/DashiboardPage.tsx#L472-L486)) plus the right-rail pipeline list
   ([:698-718](src/pages/DashiboardPage.tsx#L698-L718)) and a "New" action
   ([:487-489](src/pages/DashiboardPage.tsx#L487-L489), dialog
   [:809-819](src/pages/DashiboardPage.tsx#L809-L819)). The host expects to browse and switch
   between several saved pipelines, not to edit one. **Counterpart:** the artifact registry,
   filtered to `structured_data` — `api.artifacts.list("structured_data")` returns one entry
   per alias ([api.ts:882-885](src/lib/api.ts#L882-L885)).

2. **`isToolEnabled` — "this pipeline is callable by an agent."** State on the model
   ([:72](src/pages/DashiboardPage.tsx#L72)), a clickable badge
   ([:503-505](src/pages/DashiboardPage.tsx#L503-L505)), a toggle
   ([:385](src/pages/DashiboardPage.tsx#L385)), and a repeat in the rail
   ([:713](src/pages/DashiboardPage.tsx#L713)). This is the **only** affordance on the page
   that expresses the actual integration. **Counterpart:** whether any AgentGraph node
   references this artifact as its `pipeline_artifact`. Note it is modelled here as a
   *property of the pipeline*, which is wrong — the relationship lives on the node. It should
   become a read-only "used by N nodes" indication, not a toggle. **Worth confirming with the
   product owner** whether it should be surfaced at all.

3. **Results are three-way: statistics / visualization / logs.** The tabs
   ([:755-766](src/pages/DashiboardPage.tsx#L755-L766)) and their panes
   ([:768-802](src/pages/DashiboardPage.tsx#L768-L802)). This maps almost exactly onto
   DashiBoard's existing Spreadsheet / Visualization / Graph panes
   (`00-dashiboard-context.md` §"The current frontend") — arrived at independently, which is
   mild evidence the split is natural. **Counterpart:** the result panes decision §7 rebuilds.

4. **Templates as a way in.** ([:222-226](src/pages/DashiboardPage.tsx#L222-L226),
   [:519-530](src/pages/DashiboardPage.tsx#L519-L530)), shown *only when the canvas is
   empty*. **Counterpart:** decision §2's "importing an existing config … to start a draft
   from a previous pipeline and adapt it". The empty-state trigger is the right instinct and
   worth keeping.

Two smaller ones: **per-node status glyphs** on the card
([:573-575](src/pages/DashiboardPage.tsx#L573-L575)) and a **progress bar + append-only
execution log** ([:516](src/pages/DashiboardPage.tsx#L516),
[:672-687](src/pages/DashiboardPage.tsx#L672-L687)). Those have a real counterpart in
ExperimentTracking's opt-in `run_id` progress events (`02-stack.md`), so the *shape* of the
expectation survives even though the simulation producing it does not.

### 1c-bis. A second dead page, of a different kind

`src/pages/Index.tsx` is an unrouted Lovable stub: `App.tsx` maps `/` to `ChatPage`, nothing
imports `Index`, and the file carries `data-lovable-blank-page-placeholder="REMOVE_THIS"`
(`:9`) over a hardcoded `#fcfbf8` ground (`:8`). Filed separately from the inventory above
because it is a different animal — `DashiboardPage` is filler inside a *live* route, this is
dead by routing. It is a deletion candidate, and deliberately not worth tokenising: doing so
would make an abandoned file look maintained. (Found 2026-09-09 during the colour sweep.)

### 1d. What the code cannot tell you

- Whether the pipeline **switcher** is wanted, or whether the embedded UI should edit exactly
  the one config the host navigated to. The code shows a switcher, but the code is a mock.
  **Product owner.**
- Whether `isToolEnabled` should be visible, and if so on which side of the relationship.
  **Product owner.**
- Whether `/dashiboard` should remain a top-level destination at all, or become reachable
  only from a node's artifact picker. Today it is both a sidebar entry
  ([AppSidebar.tsx:31](src/components/AppSidebar.tsx#L31)) and a navigation target from
  `GraphBuilderPage` ([:1234](src/pages/GraphBuilderPage.tsx#L1234),
  [:1264](src/pages/GraphBuilderPage.tsx#L1264),
  [:1559](src/pages/GraphBuilderPage.tsx#L1559)). **Product owner.**

### 1e. What in this app depends on the discarded model

Answering the launch prompt's question directly — **almost nothing**, and this is the good
news:

- `GraphMinimap` is imported by exactly two files: `DashiboardPage` and `GraphBuilderPage`
  ([GraphMinimap.tsx](src/components/GraphMinimap.tsx) consumers). Deleting the Dashiboard
  page leaves the component alive for the graph builder, unchanged.
- `PipelineNode` / `PipelineConnection` / `NodeResult` / `Pipeline` are declared inside
  `DashiboardPage.tsx` and exported nowhere — they are `interface`/`type` declarations at
  [:40-73](src/pages/DashiboardPage.tsx#L40-L73) with no `export` keyword.
- The one real cross-page coupling is `dashiboardPipelineId` and the shared
  `PipelineSummary` list — covered in section 8.
- `PAGE_CONTEXTS["/dashiboard"]`
  ([AppLayout.tsx:9](src/components/AppLayout.tsx#L9)) needs its summary rewritten, since it
  currently promises "run executions, and enable pipelines as agent tools".
- `ChatWidget` renders a "Dashiboard pipelines" context section
  ([ChatWidget.tsx:209-214](src/components/ChatWidget.tsx#L209-L214)) from the same mock list.
- The smoke test mounts the page
  ([pages.smoke.test.tsx:39](src/test/integration/pages.smoke.test.tsx#L39)); its entry moves
  or goes with the page.

---

## 2. THE EMBEDDING CONTRACT

### 2a. The ground this app actually offers

Six facts decide most of this, and several of them are the opposite of what one would assume.

**There is no session to share.** No login, no cookie, no `credentials:` on any fetch.
Authentication is one static bearer token read from a build-time env var
([api.ts:250](src/lib/api.ts#L250)) and attached only if present
([api.ts:604](src/lib/api.ts#L604)) — and `.env` does not set it (it sets only
`VITE_METAGRAPH_API_URL` and `VITE_APP_MODE`). The nearest thing to identity is
`getClientId()` ([api.ts:181-193](src/lib/api.ts#L181-L193)), a `localStorage` UUID used as
the workspace lock's `opened_by`. **So "can the embedded UI share auth or session" has a flat
answer: there is nothing to share, under any mechanism.** That removes what is normally the
strongest argument against an iframe.

**There is no CSP.** No `Content-Security-Policy` meta tag in
[index.html](index.html), no header configuration anywhere in the repository (grepped across
the tree excluding `node_modules`, `dist`, `coverage`). The build is static assets
([dist/assets](dist/assets)) with no server config committed. So no CSP blocks an iframe
today — and equally, nothing constrains one. See the security note in 2f.

**Dark mode does not work.** `next-themes` is a dependency, but `useTheme` is called in
exactly one place — the vendored `components/ui/sonner.tsx`
([:1](src/components/ui/sonner.tsx#L1), [:7](src/components/ui/sonner.tsx#L7)) — and **no
`ThemeProvider` is mounted anywhere**; [App.tsx:29-63](src/App.tsx#L29-L63) wraps the tree in
QueryClient, Tooltip, Router, AppData, Chat and AppLayout, and none of them is a theme
provider. Nothing writes `.dark` to `document.documentElement` (grepped for `classList`,
`documentElement`). Tailwind is configured `darkMode: ["class"]`
([tailwind.config.ts:5](tailwind.config.ts#L5)), so the entire `.dark` block at
[index.css:62-99](src/index.css#L62-L99) and the 10 `dark:` variants in `src/` are
unreachable. **Theme synchronisation across an embed boundary is therefore a future problem,
not a present one** — but it is one an iframe must be designed for from the start, because
retrofitting it is exactly the kind of thing decision §11 warns about.

**The assistant panel never had access to page state.** This is the finding that most changes
the calculus. `AppLayout` looks up a static per-route summary by exact pathname
([AppLayout.tsx:7-17](src/components/AppLayout.tsx#L7-L17),
[:21](src/components/AppLayout.tsx#L21)) and passes it to `ChatWidget`
([:33](src/components/AppLayout.tsx#L33)). `ChatWidget` then assembles its context
([ChatWidget.tsx:147-228](src/components/ChatWidget.tsx#L147-L228)) from exactly three
sources: **router state** (`location.pathname`, `location.search`, `location.hash` —
[:148](src/components/ChatWidget.tsx#L148),
[:156-158](src/components/ChatWidget.tsx#L156-L158), and URL params broken out at
[:162-163](src/components/ChatWidget.tsx#L162-L163)), **the static summary string**
([:165-176](src/components/ChatWidget.tsx#L165-L176)), and **`AppDataContext` globals**
([:177-214](src/components/ChatWidget.tsx#L177-L214)). It reads no page component state,
because there is no mechanism by which it could — pages do not publish state to it.

**Consequence: an iframe costs the assistant panel nothing.** Whatever the embedded UI puts
in the URL, the widget sees; that is all it ever saw. A React-component embed would gain no
assistant context either, unless new plumbing were built — and that plumbing (page publishes
state to a context) would work identically for an iframe over `postMessage`.

**Query parameters have two established conventions**, both in `GraphBuilderPage`:

- **Durable selection**, bidirectionally synced with persisted state so the URL is
  "shareable / reload-safe" ([:479-492](src/pages/GraphBuilderPage.tsx#L479-L492)) — `?id=`.
- **Transient command**, read once then stripped with `replace: true`
  ([:600-609](src/pages/GraphBuilderPage.tsx#L600-L609)) — `?issues=1`.

`?pipeline=` should follow the first. Today it follows neither: it is **written** at
[:1234](src/pages/GraphBuilderPage.tsx#L1234) and
[:1264](src/pages/GraphBuilderPage.tsx#L1264) and **never read**, because `DashiboardPage`
imports no router hook. It is a dead link.

**The build is one 2.4 MB chunk.** [dist/assets](dist/assets) contains a single
`index-*.js` (2,456,626 bytes) and one `index-*.css` (80,625 bytes); there is no
`build.rollupOptions` and no `base` in [vite.config.ts](vite.config.ts). Anything compiled
into this build lands in that chunk, loaded on every route.

### 2b. The mechanisms

#### (i) iframe + postMessage

*What it costs.* A second document: two runtimes, two bundles, ~an extra full page load on
first navigation to `/dashiboard`. Overlays inside the frame are clipped to the frame's box —
a DashiBoard modal cannot dim this app's sidebar. Focus and `Escape` handling are split
across documents. Deep linking needs explicit relaying in both directions.

*What breaks.* Nothing structural.

- **react-router / `?pipeline=`** — the parent keeps owning the route. `/dashiboard?pipeline=X`
  stays a parent URL; the page reads it with `useSearchParams` and passes it into the frame's
  `src` (or over `postMessage` after a handshake). Because `PAGE_CONTEXTS` is keyed on
  `location.pathname` ([AppLayout.tsx:21](src/components/AppLayout.tsx#L21)), which excludes
  the query string, the existing entry keeps matching. **Constraint this imposes on
  DashiBoard:** the frame must post its selection back so the parent can mirror it into the
  URL, or the assistant panel and browser history both go blind. This is the one real
  requirement the iframe adds, and it is cheap.
- **AppLayout chrome / assistant panel** — untouched. `ChatWidget` is a sibling of `<main>`
  in the parent DOM ([AppLayout.tsx:32-33](src/components/AppLayout.tsx#L32-L33)), so it
  floats over the frame normally. Per 2a it loses no context it ever had.
- **Tailwind / shadcn theming** — the frame has its own document, so no class collisions
  (relevant because `prefix: ""`, [tailwind.config.ts:7](tailwind.config.ts#L7)). The cost is
  that tokens must be *transmitted*: see section 3 for the exact list and the mechanism.
- **next-themes** — nothing to sync today; when a provider is added, one `postMessage` on
  change.
- **Fonts and assets** — the frame loads its own. Inter comes from a Google Fonts
  `@import` ([index.css:1](src/index.css#L1)), which the frame can simply repeat. Since
  ExperimentTracking serves the frame's assets, they are same-origin *inside* the frame.
- **CSP** — none exists; adding `frame-src` for the resolved DashiBoard origin is
  straightforward, and I recommend it (2f).
- **Auth/session** — nothing to share (2a). The frame authenticates to Julia however Julia
  wants, independently. Note that `requestBlob` already documents the general constraint:
  *"An `<img src>` or `<iframe src>` cannot carry the Authorization header"*
  ([api.ts:628-630](src/lib/api.ts#L628-L630)) — a real limit, but inert here because
  DashiBoard's own origin is not behind this app's bearer token.

#### (ii) npm package exporting a React component

*What it costs.* The most expensive option, and the cost is structural rather than
incremental.

- **It fixes DashiBoard's framework to React forever.** Stated plainly because it is the
  point of the question.
- **Peer-dependency lockstep.** [vite.config.ts:20](vite.config.ts#L20) already dedupes
  `react`, `react-dom`, `react/jsx-runtime`, `react/jsx-dev-runtime`, `@tanstack/react-query`
  and `@tanstack/query-core` — the template ships that guard because duplicate instances of
  these break hooks and context silently. A separately-published component package makes that
  guard a standing contract between two repositories on two release cadences. Every React
  major upgrade becomes a two-repository coordination.
- **CORS is required anyway.** The component runs on *this* origin, so its calls to Julia are
  cross-origin regardless — the exact point decision §10 makes. The iframe's same-origin
  property is given up for nothing.
- **Tailwind collision.** With `prefix: ""` ([tailwind.config.ts:7](tailwind.config.ts#L7))
  and a shared document, the package must either ship pre-compiled scoped CSS or have its
  source scanned by this app's `content` globs
  ([tailwind.config.ts:6](tailwind.config.ts#L6)) — which today cover only `./src/**`, so
  `node_modules/<pkg>` would need adding, and every class the package uses would be
  purge-visible to this app and vice versa.
- **Bundle.** Straight into the single 2.4 MB chunk, on every route.

*What it buys.* Genuine overlay compositing (a DashiBoard dialog can cover the sidebar), one
runtime, direct prop-passing instead of `postMessage`, and shared `AppDataContext`. Under
decision §2's "one config document each way" these are worth very little: there is no
high-frequency, high-fidelity interaction to preserve.

#### (iii) Module Federation

Every cost of (ii) — same framework lock, same peer-dependency lockstep, same Tailwind
collision, same CORS — plus a build-system commitment. This project builds with
`@vitejs/plugin-react-swc` ([vite.config.ts:2](vite.config.ts#L2),
[:15](vite.config.ts#L15)) and would need `@originjs/vite-plugin-federation` or equivalent on
both sides, with the shared-module graph declared consistently in two repositories. It
converts a build-time coupling into a *runtime* one that can still fail at load. It buys
nothing over (ii) except avoiding a republish on change, which an iframe gets for free. **Not
recommended under any reading.**

#### (iv) Web component

Frees DashiBoard's framework, like the iframe. Its real problem is the boundary. Shadow DOM
gives style isolation but blocks the CSS custom properties this app themes with — inherited
properties do pierce shadow boundaries, so `--primary` and friends would actually reach in,
but Tailwind's *generated utility classes* would not, so DashiBoard would have to ship its
own compiled CSS inside the shadow root anyway. Without shadow DOM, `prefix: ""` guarantees
collisions. Meanwhile the calls to Julia are same-origin-with-this-app, i.e. cross-origin to
Julia — CORS returns. So: the iframe's framework freedom, without the iframe's origin
property, plus a styling problem the iframe does not have.

#### (v) Build-time vendored bundle

Copy DashiBoard's built assets into [public/](public) or `src/`. It has one virtue — no
network dependency on the Julia host at load — and it is otherwise the worst option: version
drift with no version signal, a manual copy step in a repository whose CI runs only
typecheck/lint/test ([.github/workflows/ci.yml](.github/workflows/ci.yml)), and the config
artifact still has to cross the boundary at runtime anyway. It also directly contradicts
decision §11: it is the most expensive mechanism to change later. **Not recommended.**

### 2c. Recommendation

**The iframe, pointed at the resolved `dashi` RemoteService URL, with a `postMessage`
contract for the config document, theme and selection.**

**I confirm the consequence: this leaves DashiBoard's frontend framework free. SolidJS can
stay.** I am recommending it in full knowledge that it removes the constraint which would
have forced React, and I think removing that constraint is a benefit rather than a side
effect — decision §7 rebuilds the whole frontend, and forcing a framework migration into that
same change would multiply the risk for no gain this host can name.

The reasoning, in order of weight:

1. **The payload does not justify a tighter binding.** Decision §2 fixes the boundary traffic
   at one config document each way. Every advantage of a component embed is an advantage in
   *fine-grained* interaction — shared context, prop-passing, overlay compositing. None of
   that is being asked for.

2. **The privileged relationship this app has with the Julia side is already runtime, and
   already user-editable.** `GET /v1/services` with per-field provenance, `PUT .../connection`
   and `GET .../health` are all consumed and shipped (section 7). The DashiBoard URL is a
   value an operator can change on a running system through this app's own UI
   ([ConnectionPanel.tsx:41-52](src/components/ConnectionPanel.tsx#L41-L52)). An iframe `src`
   consumes that value directly. A compiled-in React component cannot — it would be the one
   part of the DashiBoard relationship pinned at build time, in an app that already has a
   first-class UI for changing it at runtime. That is backwards.

3. **Decision §11's test points here.** "Prefer the option that can be changed later without
   re-authoring the UI." An iframe can be replaced by a component embed later; a component
   embed cannot be replaced by an iframe without having chosen React, and cannot be
   *un*-chosen at all if DashiBoard's standalone UI was built React-only to satisfy it.

4. **The iframe's usual costs are absent here.** No session to share, no CSP to negotiate, and
   an assistant panel that never read page state anyway (2a).

4b. **[amended] It also removes a CORS problem rather than creating one.** Decision §10 now
   records that ExperimentTracking has *no CORS handling whatsoever* — two response headers, no
   `Access-Control-Allow-Origin`, no `OPTIONS` route — so every preflighted cross-origin `POST`
   against it fails outright. Under the iframe, nexus-weaver-pro never calls ExperimentTracking:
   the frame does, same-origin, and this app talks only to AgentGraph as it already does. So the
   host boundary needs no CORS at all. A compiled-in React component would put those Julia calls
   on this app's origin and make configured CORS a hard prerequisite for the embed to function
   anywhere — including in development, where §10 notes it blocks immediately. I did not have
   this finding when I made the recommendation; it points the same way.

5. **This app has already accepted the analogous split.** `GraphBuilderPage` renders the graph
   but deliberately refuses to save it, with the reasoning written in the source: *"The
   builder is a VIEW of the resolved topology; it cannot re-serialize the authored document
   without dropping what the canvas does not model"*
   ([:1031-1035](src/pages/GraphBuilderPage.tsx#L1031-L1035)); editing goes elsewhere. A
   `/dashiboard` route that hosts an authoring surface it does not own is the same shape, and
   this codebase has already found that shape acceptable.

**Where I would revisit it.** If the product owner wants a DashiBoard *node inspector* to
appear inside this app's assistant side panel — i.e. real compositing of DashiBoard UI with
host chrome — the iframe stops being adequate and (ii) becomes the honest answer. Nothing in
decisions §1-§11 asks for that, but it is the specific requirement that would flip the call,
and it is worth putting to the owner before DashiBoard's framework is settled, because that
decision is expensive to reverse in the other direction.

### 2d. The contract I would write

```
Parent (nexus-weaver-pro)                    Frame (DashiBoard, served by ExperimentTracking)
─────────────────────────                    ────────────────────────────────────────────────
  <iframe src={dashiUrl + "/embed"}>
    ── postMessage ──────────────────────▶   { type: "host:init", version: 1,
                                               tokens: {...},        // section 3
                                               theme: "light"|"dark",
                                               config: {...} | null, // the doc to edit
                                               configRef: string | null,
                                               readOnly: boolean }
  ◀──────────────────────────────────────    { type: "embed:ready", version: 1 }
    ── on theme change ─────────────────▶    { type: "host:theme", theme }
  ◀──────────────────────────────────────    { type: "embed:selection", nodeId | null }
  ◀──────────────────────────────────────    { type: "embed:dirty", dirty: boolean }
  ◀──────────────────────────────────────    { type: "embed:save",
                                               config: { nodes, groups, filters },
                                               requiredColumns: string[],
                                               producedColumns: string[],
                                               suggestedAlias?: string }
    ── after registry write ────────────▶    { type: "host:saved", configRef, version }
                                             │ or { type: "host:save-failed", detail }
```

Rules I would fix now, because they are cheap now and expensive later:

- **Both sides check `event.origin`** against the resolved service URL's origin, and the
  parent checks `event.source === iframeRef.current.contentWindow`. Non-negotiable given 2f.
- **`version` on every message**, so the two repositories can skew.
- **The frame never writes to the artifact registry.** It hands the parent a document; the
  parent owns the registry call. This keeps the AgentGraph API key on one side and means
  DashiBoard needs no knowledge of `/v1/artifacts`.
- **The parent owns the URL.** On `embed:selection` it mirrors into `?pipeline=`/`?node=` with
  `replace: true`, following the `?id=` convention
  ([GraphBuilderPage.tsx:479-492](src/pages/GraphBuilderPage.tsx#L479-L492)).
- **`embed:dirty` gates navigation**, so this app can warn before leaving `/dashiboard` with
  unsaved work — impossible without it, since the parent cannot see into the frame.
- **A handshake timeout** with a visible failure. This app's house style is emphatic that a
  silent fallback is worse than a visible failure
  ([toolRegistry.ts:130-134](src/lib/toolRegistry.ts#L130-L134),
  [backendRegistryStore.ts:10-19](src/lib/backendRegistryStore.ts#L10-L19)); an iframe that
  never answers must render an error, never an empty canvas.

### 2e. What this app must build (iframe path)

Small, and all of it in this repository:

1. Rewrite `DashiboardPage.tsx` to: resolve the `dashi` URL via `api.services.list()`, render
   the frame, run the handshake, mirror selection into the URL, and handle `embed:save` by
   writing to `/v1/artifacts`.
2. A reachability pre-check before rendering the frame — `api.services.health("dashi")`
   already exists ([api.ts:983-985](src/lib/api.ts#L983-L985)) and its unreachable state
   already renders launch instructions
   ([ConnectionPanel.tsx:93-110](src/components/ConnectionPanel.tsx#L93-L110)). Reuse that
   rather than showing a blank frame.
3. Rewrite `PAGE_CONTEXTS["/dashiboard"]`
   ([AppLayout.tsx:9](src/components/AppLayout.tsx#L9)).
4. Replace the `PipelineSummary` mock list with the artifact registry (section 8).
5. The artifact **versioning** fix (section 8) — required, and independent of mechanism.
6. `frame-src` CSP and iframe `sandbox` attributes (2f).

### 2f. A security note that is not optional

The URL this app would load in an iframe is **user-editable and server-persisted**.
`ConnectionPanel` exposes an edit form for `connection.url`
([ConnectionPanel.tsx:115-120](src/components/ConnectionPanel.tsx#L115-L120)), wired through
`ServiceDetailPage` ([:182-186](src/pages/ServiceDetailPage.tsx#L182-L186)) to
`api.services.updateConnection` ([api.ts:992-1000](src/lib/api.ts#L992-L1000)), which writes
the `configured` layer — *"a row in Postgres, written by THIS panel"*
([ConnectionPanel.tsx:44](src/components/ConnectionPanel.tsx#L44)).

So anyone who can reach the AgentGraph API can choose what document this app frames. Today
that is harmless because nothing frames it. Under the iframe recommendation it becomes a
path to loading attacker-chosen content inside the app's origin's frame. Mitigations, all
cheap:

- A real CSP with an explicit `frame-src` allowlist, rather than the current absence of one.
- `sandbox="allow-scripts allow-forms allow-same-origin"` on the frame — noting that
  `allow-scripts` together with `allow-same-origin` is only safe because the frame is a
  *different* origin from this app; it must never be pointed at this app's own origin.
- Strict `event.origin` checks on every `postMessage` (2d), never `"*"` as `targetOrigin`.
- Treat everything arriving on `embed:save` as untrusted input and validate it before
  registering it.

This is not an argument against the iframe — the component embed would *execute* that party's
code directly, which is strictly worse. It is an argument for doing the iframe properly.

---

## 3. Design tokens

### 3a. The one convention that matters most

Tokens are stored as **bare HSL triplets**, not colours:
`--primary: 174 62% 38%` ([index.css:19](src/index.css#L19)). They are only usable through
`hsl(var(--token))` — Tailwind does the wrapping
([tailwind.config.ts:26-29](tailwind.config.ts#L26-L29)). **An embedded UI that writes
`color: var(--primary)` gets an invalid value and renders unstyled.** Every consumer must
write `hsl(var(--primary))`, and `hsl(var(--muted) / 0.3)` for alpha.

The exemplar for a third-party widget is `agGridTheme.ts`
([:11-24](src/lib/agGridTheme.ts#L11-L24)), whose comment states the rule and the payoff:
*"ag-grid's theme parameters compile to CSS custom properties themselves, so these references
resolve at paint time — which means light/dark follows the app automatically, with no theme
listener and no second palette to keep in step."* It also sets `fontFamily: "inherit"`
([:19](src/lib/agGridTheme.ts#L19)). **This is the pattern to copy.**

The counter-example is `GraphMinimap`, which hardcodes hex
([:25-38](src/components/GraphMinimap.tsx#L25-L38): `#0d9488`, `#3b82f6`, `#f59e0b`,
`#22c55e`, `#6b7280`, `#ef4444`) plus a literal `fill="#9ca3af"` on labels
([:131](src/components/GraphMinimap.tsx#L131)) and `#4b5563` edges
([:91](src/components/GraphMinimap.tsx#L91)). It will not follow a theme. Do not copy it.

### 3b. The complete token list to transmit

Defined in `:root` ([index.css:9-60](src/index.css#L9-L60)) and overridden in `.dark`
([:62-99](src/index.css#L62-L99)).

**Core shadcn** — all present in both blocks: `--background`, `--foreground`, `--card`,
`--card-foreground`, `--popover`, `--popover-foreground`, `--primary`,
`--primary-foreground`, `--secondary`, `--secondary-foreground`, `--muted`,
`--muted-foreground`, `--accent`, `--accent-foreground`, `--destructive`,
`--destructive-foreground`, `--border`, `--input`, `--ring`.

**Beyond stock shadcn** — this app adds three status scales, mapped in Tailwind at
[tailwind.config.ts:54-65](tailwind.config.ts#L54-L65): `--success` / `--success-foreground`,
`--warning` / `--warning-foreground`, `--info` / `--info-foreground`
([index.css:50-55](src/index.css#L50-L55)). The placeholder uses all three
([DashiboardPage.tsx:91-95](src/pages/DashiboardPage.tsx#L91-L95),
[:574-575](src/pages/DashiboardPage.tsx#L574-L575)), as do the service status dots
([servicePing.ts:24-29](src/lib/servicePing.ts#L24-L29)).

**Sidebar scale** — eight tokens ([index.css:41-48](src/index.css#L41-L48),
[tailwind.config.ts:66-75](tailwind.config.ts#L66-L75)). Host chrome only; an embedded UI
should not use them.

**Radius** — `--radius: 0.5rem` ([index.css:39](src/index.css#L39)), with Tailwind deriving
the scale ([tailwind.config.ts:77-81](tailwind.config.ts#L77-L81)):
`lg = var(--radius)`, `md = calc(var(--radius) - 2px)`, `sm = calc(var(--radius) - 4px)`.
**Transmit `--radius` and derive the same way** — do not hardcode 8px.

**Effects** — `--gradient-primary`, `--shadow-card`, `--shadow-elevated`, `--primary-glow`
([index.css:21](src/index.css#L21), [:57-59](src/index.css#L57-L59)), surfaced as utilities
`.gradient-primary`, `.shadow-card`, `.shadow-elevated`
([index.css:113-122](src/index.css#L113-L122)). Used on cards and accents
([DashiboardPage.tsx:463](src/pages/DashiboardPage.tsx#L463),
[:673](src/pages/DashiboardPage.tsx#L673)).

**Typography** — Inter, loaded by a Google Fonts `@import`
([index.css:1](src/index.css#L1)), declared both in Tailwind
([tailwind.config.ts:17-19](tailwind.config.ts#L17-L19)) and directly on `body`
([index.css:109](src/index.css#L109)). The frame should repeat the same import.

**Motion** — `fade-in` (0.3s ease-out) and `pulse-subtle` (2s)
([tailwind.config.ts:91-104](tailwind.config.ts#L91-L104)). `animate-fade-in` is the standard
page-enter ([DashiboardPage.tsx:459](src/pages/DashiboardPage.tsx#L459)).

**Spacing** — there is no custom spacing scale. Stock Tailwind. What exists is an unwritten
*density* convention worth naming, since it is what makes a foreign UI look foreign: this app
runs small. Body text is `text-xs`, secondary text `text-[10px]`, badges `text-[9px]` /
`text-[8px]`, buttons `h-7`/`h-8`, icons `h-3 w-3`, gaps `gap-1.5`/`gap-2`, card padding
`p-2.5`/`p-3` ([DashiboardPage.tsx:500-513](src/pages/DashiboardPage.tsx#L500-L513),
[:565-605](src/pages/DashiboardPage.tsx#L565-L605)). An embedded UI at default shadcn sizing
will read as noticeably larger than its host.

### 3c. A real bug to fix here

**`.dark` does not override the status colours or the effects.** `--success`, `--warning`,
`--info` and their foregrounds are defined only in `:root`
([index.css:50-55](src/index.css#L50-L55)), and so are `--primary-glow`
([:21](src/index.css#L21)), `--gradient-primary`, `--shadow-card` and `--shadow-elevated`
([:57-59](src/index.css#L57-L59)). The `.dark` block ends at
[:99](src/index.css#L99) without redefining any of them.

Today this is invisible because dark mode is unreachable (2a). The moment a `ThemeProvider` is
mounted, dark mode ships light-mode success/warning/info fills and light-mode shadows tuned
for a light ground. Since transmitting tokens to an embedded UI is exactly what forces the
palette to be complete, **fix this before or as part of the embed work**, not after.

**[amended 2026-09-09] Authoring the missing dark values is necessary but not sufficient — one
of them is wired past.** The effect tokens are not consumed through `tailwind.config.ts` at all
(it extends neither `boxShadow` nor `backgroundImage`); they are consumed by three hand-written
utilities in `index.css`'s own `@layer utilities`
([index.css:113-122](src/index.css#L113-L122)) — and the three do not behave alike:

| Token | Status | Mechanism |
|---|---|---|
| `--shadow-card` | **live** | `.shadow-card` is `box-shadow: var(--shadow-card)` — 28 call sites |
| `--shadow-elevated` | **live** | same — 1 call site |
| `--gradient-primary` | **never dereferenced** | `.gradient-primary` **hardcodes** `linear-gradient(135deg, hsl(174 62% 38%), hsl(174 62% 48%))` — but the class has **26 call sites** |
| `--primary-glow` | **dead** | no consumer anywhere in `src/` or `tailwind.config.ts` |

`grep -rn "var(--gradient-primary)"` over `src/` and `tailwind.config.ts` returns nothing: the
token is authored in `:root` and read by nobody, while the utility duplicates its value by hand.

So defining `--gradient-primary` under `.dark` changes nothing. All 26 call sites keep painting
the light-mode teal on a dark ground — the floating chat launcher
([ChatWidget.tsx:356](src/components/ChatWidget.tsx#L356)), the message avatars
([MessageBubble.tsx:27](src/components/MessageBubble.tsx#L27)), the sandbox send button
([SandboxChatDialog.tsx:330](src/components/SandboxChatDialog.tsx#L330)). It is the failure mode
worth naming, because the token *looks* authored: the palette reads as complete in `index.css`
while the most prominent accent in the app ignores the theme. The fix is one line —
`.gradient-primary { background: var(--gradient-primary); }` — and is plausibly what the token
was written for before someone stopped short of wiring it.

The two shadow tokens do respond, and genuinely need dark values rather than inheritance: both
are near-black at low alpha (`hsl(220 20% 10% / 0.06)`), which all but vanishes on a dark
ground, so cards lose their elevation entirely.

**Status: fixed in the working tree on 2026-09-09** (uncommitted at time of writing) by the
session that owns theming. `.gradient-primary` now reads `var(--gradient-primary)`, the light
token being byte-identical to the literal it replaced; the three status scales, both shadows,
`--primary-glow` and `--gradient-primary` gained dark values; and `ThemeProvider`
(`attribute="class"`, matching `darkMode: ["class"]`) is mounted outermost in `App.tsx`, which
also fixes `ui/sonner.tsx` calling `useTheme()` with no provider above it. Coverage verified by
walking both blocks: `:root` 38 tokens, `.dark` 37, the sole gap being `--radius`, which is a
length and needs none. **So 2a's "dark mode is unreachable" is now historical** — the embed
design should assume a live theme and plan to transmit it across the frame boundary, as §2d's
`host:theme` message already provides for.

On `--primary-glow` I recommended skipping a dark value, since nothing reads it; the
implementing session kept it with a comment saying so, and that is the better call — an absent
token is the same shape of ambiguity that produced this finding, and a comment settles "bug or
deliberate?" permanently for less than the cost of re-deriving it.

**Two residuals the fix exposes rather than causes.** Both were latent only because `.dark` was
unreachable:

- **Ten `dark:` utilities are now live having never rendered for anyone** — unreviewed by
  construction. `EditForm.tsx:1129`, `FindingsPanel.tsx:36`, `PauseCard.tsx:37`,
  `structured/FriendlyJsonView.tsx:132-133`, `ui/alert.tsx:12` are amber/emerald/purple text
  pairs and low risk. `ui/chart.tsx:7` is not: `const THEMES = { light: "", dark: ".dark" }` is
  an entire second recharts theme path that has never executed once.
- **Hardcoded hex does not follow the theme**, and `GraphMinimap` is the load-bearing case
  (3a): its palette (`:25-38`), label fill (`:131`) and edge stroke (`:91`) are literals.
  `agGridTheme.ts:11-24` is the correct template. `DocumentTopicsPane.tsx:25-28` also hardcodes
  hex but carries explicit `{light, dark}` pairs and is fine.

  **This is worse than "it won't follow the theme", and not in the direction I first stated.**
  I claimed the labels would go mid-grey on a dark ground; that is backwards, and the
  measurement is owed to the theming session, which computed it and corrected me. Contrast
  against `--card` in each mode (`#ffffff` light, `hsl(220 20% 10%)` = `#14181f` dark),
  recomputed here independently and agreeing to two decimals:

  | | raw light | raw dark | @ `opacity={0.5}` light | @ dark |
  |---|---|---|---|---|
  | label `#9ca3af` (`:131`) | **2.54** | 7.01 | — | — |
  | edge `#4b5563` (`:91`) | 7.56 | **2.35** | **2.34** | **1.47** |
  | conditional edge `#f59e0b` | **2.15** | 8.29 | **1.48** | **2.96** |

  `#9ca3af` is grey-400 — a *light* grey — so it gains contrast on dark and fails on the white
  card it has always shipped against. Judged at the right thresholds (4.5:1 for the labels,
  which are text at `fontSize={7}`; 3:1 for edges as non-text graphics under WCAG SC 1.4.11):
  the labels fail in light and pass in dark, and **every edge case fails once `opacity={0.5}`
  is composited — all four cells, both modes.**

  So there are two independent defects that partially cancelled. The palette reads as authored
  for a dark ground the app never had (grey-400 labels, amber edges), *and* a 0.5 opacity was
  applied on top of colours already chosen dark. Light mode looked acceptable only because the
  first defect offset the second.

  **Fixed 2026-09-09** (uncommitted): `--muted-foreground` for labels and plain edges, semantic
  tokens for the dots, plain-edge opacity 0.5 → 0.85 and idle-dot opacity 0.6 → 0.85. Plain edge
  2.34/1.47 → **3.65/3.97**; label 2.54/7.01 → **4.89/5.01**. No hex literals remain in the file.

  > **Do not use `--border` for a mark that must be seen.** An earlier draft of this section
  > recommended `hsl(var(--border))` for the edges. That was wrong and would have made light
  > mode worse: measured against `--card`, `--border` is **1.27 light / 1.25 dark at full
  > opacity** — below the 2.34 the failing literal already achieved. It is a subtle-divider
  > token, and its correct use in `agGridTheme.ts:14` for grid rules does not generalise, because
  > a rule is meant to recede and an edge is meant to read. Measured alternatives against
  > `--card` (light / dark): `--muted-foreground` 4.89 / 5.01 · `--primary` 3.33 / 8.37 ·
  > `--success` 3.17 / 7.57 · `--info` 2.88 / 7.29 · `--destructive` 4.80 / 3.49 ·
  > `--warning` 2.13 / 9.34.

  **A palette defect this exposed, larger than the minimap.** `--warning` (2.13) and `--info`
  (2.88) cannot reach even 3:1 on the light card at *full* opacity — no opacity choice rescues
  them. That is not a minimap bug, and it is not only about marks: `text-warning` / `text-info`
  appear **19 times as foreground text**, where the 4.5:1 threshold applies and `--warning`
  misses by more than half. Seven are small type — `ConnectionPanel.tsx:96` (the 11px wrong-port
  hint quoted in 7b), `:87` (11px mono service-error detail), `EditForm.tsx:906`/`:933` (10px
  publish-guard warnings), and 9px badges at `EditForm.tsx:889`, `OperationsList.tsx:129`,
  `ProfilePage.tsx:223`. The nine `bg-warning/*` tints are fine. The dark column passes
  throughout (9.34 / 7.29), so this is a **light-mode-only palette defect** — the same signature
  as the minimap: colours that behave as though chosen against a dark ground. It wants
  `--warning`/`--info` darkened in `:root`, not local substitutions; the minimap's conditional
  edge would then inherit the fix instead of staying a special case.

  **Fixed 2026-09-09** (uncommitted, light `:root` only): `--warning` L50%→33% (2.13 → 4.61),
  `--info` L50%→39% (2.88 → 4.50). Dark untouched, already 9.34 / 7.29.

  **The pattern is the whole palette, not two tokens.** Measured on the light card, all four
  status/brand colours were authored below the 4.5:1 text threshold:

  | token | on white | text sites | clears at |
  |---|---|---|---|
  | `--warning` | 2.13 | 19 combined | L33% → 4.61 ✔ shipped |
  | `--info` | 2.88 | (with warning) | L39% → 4.50 ✔ shipped |
  | `--success` | 3.17 | **23** | L32% → 4.68 — with owner |
  | `--primary` | 3.33 | **167** | L32% → 4.53 — with owner |

  **The decisive case for `--primary` is not `text-primary`.** `ui/button.tsx:12` renders the
  default variant as `bg-primary text-primary-foreground` with a white foreground, so
  white-on-primary is **3.33:1** — *the default button's own label fails the text threshold in
  the light mode that has always shipped*, independently of the 167 text usages. L32% takes it
  to 4.53. That makes it an accessibility defect that happens to also resolve 167 sites, rather
  than a brand change justified by them.

  **A `--primary` change is four coordinated edits, not one.** Its value is written out seven
  times in `:root` and nothing derives from it: `--primary` (`:19`), `--ring` (`:37`, the same
  literal), both stops of `--gradient-primary` (`:61`), plus `--primary-glow` (`:21`),
  `--sidebar-primary` (`:43`), `--sidebar-ring` (`:48`) and `--accent-foreground` (`:30`).
  Darkening `--primary` alone splits the brand in two: buttons and text at 32% while the **26
  `.gradient-primary` surfaces** (chat launcher, avatars, sandbox send) keep painting 38→48%, in
  the same views. `--ring` passes 3:1 as a focus indicator (SC 1.4.11) and needs no change for
  its own sake, but left alone it stops matching the button it rings. The sidebar pair is fine
  untouched — 48% on an always-dark ground.

  This is the same defect class as the gradient utility above: **a value duplicated rather than
  derived.** The durable fix is to express `--ring` and `--gradient-primary` in terms of
  `--primary` instead of repeating its digits, or the next brand adjustment hits this again.

  **Done 2026-09-09** (uncommitted): `--ring: var(--primary)`,
  `--sidebar-ring: var(--sidebar-primary)`, and
  `--gradient-primary: linear-gradient(135deg, hsl(var(--primary)), hsl(var(--primary-glow)))`.
  Verified value-preserving in both modes — light resolves 38%→48% and dark 48%→58%, exactly the
  literals replaced. Teal literals 14 → 8, and `--primary-glow` is no longer dead: it is the
  gradient's second stop. `--success` also went L40%→32% (3.17 → 4.68). A colour sweep took raw
  Tailwind palette utilities 29 → 0 and hex literals 8 → 3 (`#0d1117` ×2, commented as
  highlight.js's ground held deliberately in both themes; `#fcfbf8` in dead code, below).

  **⚠ The derivation couples the gradient to the still-open `--primary` decision.** Because
  `--primary-glow` does not move with `--primary`, approving L32% silently reshapes the
  gradient across all 26 `.gradient-primary` surfaces:

  | | stops | spread |
  |---|---|---|
  | today | L38% → L48% | 10 pts |
  | `--primary` → 32% | L32% → **L48%** | **16 pts (+60%)** |
  | `--primary-glow` → 42% as well | L32% → L42% | 10 pts, preserved |

  So `--primary` is not one decision but two: the accessibility fix, and whether the gradient's
  step is held. Before the derivation this would not have arisen — the gradient would simply
  have gone stale, which is worse. The refactor surfaces the choice rather than hiding it.

  **Resolved 2026-09-09** (uncommitted): the owner took both — `--primary` L38%→32% **with
  `--primary-glow` L48%→42%**, holding the 10-point step. Light `:root` only; dark stays 48/58.
  Verified: default button label (white on `--primary`) **4.53**, `text-primary` on card
  **4.53**, focus ring **4.53** against its 3:1 gate, gradient spread unchanged at 10 points,
  dark `--primary` 8.37.

  **Net for the whole palette.** Every light-mode contrast failure catalogued in this section is
  closed: the minimap's five, 19 `text-warning`/`text-info` sites, 23 `text-success`, 167
  `text-primary`, the default button's own label, and the treemap's dark-mode labels. No token
  was added; the brand reduced from seven duplicated literals to one knob with `--ring` and
  `--gradient-primary` derived from it. **For the embed contract this matters concretely**: §3b's
  token list is what an embedded UI must be handed, and it is now internally consistent in both
  modes — before today, transmitting it would have propagated the light-mode defects into
  DashiBoard's frame as well.

  **The bypass palettes were duplicates, not distinct designs.** `DocumentTopicsPane`'s chart
  hues (213/17/159/220) shadowed `--info`/`--warning`/`--success`/`--muted-foreground`
  (200/38/160/220) — a hand-rolled copy of the status scale carried as `theme: {light, dark}`
  pairs the tokens already provide. Rank 3 measured **2.82:1** on the light card as authored,
  under even the 3:1 non-text gate: a fourth surface where the light column was wrong from the
  start. It now references the tokens and inherits their corrections.

  **A latent dark-mode bug the sweep caught**, worth recording as the shape to look for: the
  11px treemap labels were `fill="#ffffff"` — fine on every light-mode series (4.50-4.88) and
  failing all four in dark (1.90-3.54), because the series lighten there. `hsl(var(--card))`
  fixes both directions with one token; re-measured at 4.50/4.61/4.68/4.89 light and
  7.29/9.34/7.57/5.01 dark. It would have shipped the instant anyone toggled the theme.

### 3d. Where `components/ui` ends and app code begins

The boundary is stated explicitly in the test config, which excludes
`src/components/ui/**` from coverage as *"shadcn primitives, vendored not authored"*
([vitest.config.ts:23](vitest.config.ts#L23)).

- **`src/components/ui/`** — 49 files, generated by the shadcn CLI per
  [components.json](components.json), aliased `@/components/ui`
  ([components.json:16](components.json#L16)). Treat as vendored: not tested, not hand-edited.
- **`src/components/`** (everything else) and **`src/pages/`** — app code, tested
  ([vitest.config.ts:18-21](vitest.config.ts#L18-L21) reports on the whole app deliberately).
- **`src/lib/`** — pure logic and API clients, the best-tested layer.

Two primitives are notable as boundary cases: `components/ui/form.tsx` is vendored but
**imported by nothing** (section 4), and `components/ui/sidebar.tsx` is the largest file in
`ui/` at 637 lines and is host chrome, not a reusable primitive.

**For an embedded UI:** it should reproduce shadcn's *visual* result from the transmitted
tokens. It should not depend on this app's `components/ui` — under the iframe it cannot, and
that is fine, since those files are themselves generated from a public CLI that DashiBoard can
run against the same `components.json` if it wants React parity, or reimplement if it stays
SolidJS.

---

## 4. Schema-driven forms, and what this app already does

### 4a. Direct answers

**Do you consume `GET /v1/graphs/schema`?** No. Zero references anywhere in `src/` (grepped
for `graphs/schema` and `/schema`; the only hits are unrelated — a PostgreSQL schema in
`knowledge.ts` and a comment in `LiveTestPopover.tsx`). The endpoint that solves this problem
already exists on the backend and this app has never called it.

**Why not?** The code cannot tell me, and I will not invent a reason. What the code *does*
show is that the app grew a different, weaker mechanism for the same job (4c) and has a
recorded incident from it (4d). **INFERRED:** the schema endpoint post-dates the forms.
Worth confirming with the AgentGraph session or the product owner.

**How are zod and react-hook-form used?** They are not.

- `zod` is a dependency ([package.json](package.json), `"zod": "^3.25.76"`) and is **imported
  zero times** in `src/`.
- `@hookform/resolvers` — **zero imports**.
- `react-hook-form` is imported by exactly one file,
  [components/ui/form.tsx](src/components/ui/form.tsx#L4) — the vendored shadcn primitive —
  and **that file is imported by nothing**.

So there are no hand-authored TypeScript schemas *and* nothing derived from the backend.
**There is no validation layer in this application at all.** Form state is `useState`, and
correctness is whatever the backend replies.

**Is there a JSON-Schema-to-zod or JSON-Schema-to-form layer?** No. No such library is a
dependency, and no such module exists in `src/`.

### 4b. Also worth knowing: TanStack Query is inert

The launch prompt asks about "TanStack Query key conventions". There are none, because the
library is not used. `QueryClientProvider` is mounted
([App.tsx:27](src/App.tsx#L27), [:30](src/App.tsx#L30)), but `useQuery` is called **zero
times** across `src/`, as are `useMutation`, `useQueryClient` and `invalidateQueries`. There
are no query keys.

Data fetching is instead:
- **`createBackendRegistryStore`** ([backendRegistryStore.ts](src/lib/backendRegistryStore.ts))
  — a hand-rolled single-flight store with a watchdog, a generation guard and pub/sub, used by
  the artifacts store ([artifacts.ts:13-18](src/lib/artifacts.ts#L13-L18)) and the services
  store. Its contract is that **any** failure leaves the list empty rather than stale, argued
  at [:10-19](src/lib/backendRegistryStore.ts#L10-L19).
- **`useEffect` + `useState`** everywhere else (e.g.
  [ServicesPage.tsx:24-50](src/pages/ServicesPage.tsx#L24-L50)).

### 4c. What exists instead

Three surfaces, none schema-driven:

**1. Raw YAML.** The primary graph-config editing surface is a text editor.
[EditForm.tsx](src/components/EditForm.tsx) holds `corrected_config_yaml` as a string
([:47-48](src/components/EditForm.tsx#L47-L48)), parses it with `js-yaml`
([:2](src/components/EditForm.tsx#L2),
[:98-106](src/components/EditForm.tsx#L98-L106)) and renders it through `CodeSurface`. The
1,253-line component is workspace/branch/publish machinery around a textarea.

**2. A four-branch widget switch.** `paramInput` in
[NodeEditorDialog.tsx:111-151](src/components/NodeEditorDialog.tsx#L111-L151) is the closest
thing to derived rendering in the codebase: `boolean` → a two-item Select
([:117-127](src/components/NodeEditorDialog.tsx#L117-L127)), `number` → numeric Input
([:128-134](src/components/NodeEditorDialog.tsx#L128-L134)), `json`/`string[]` → a JSON
Textarea ([:135-144](src/components/NodeEditorDialog.tsx#L135-L144)), everything else → text
or password ([:145-150](src/components/NodeEditorDialog.tsx#L145-L150)). No enums, no
constraints, no nesting, no validation.

**3. Name-based heuristics standing in for a schema.** This is the important one.
[toolRegistry.ts](src/lib/toolRegistry.ts) states the situation at
[:10-13](src/lib/toolRegistry.ts#L10-L13): *"The backend ships `yaml_params` as a plain
`string[]` (parameter names only). The UI needs richer hints (kind, description) to render the
right input control, so `normalizeToolParams` infers them from the raw payload."*

`inferKind` ([:54-69](src/lib/toolRegistry.ts#L54-L69)) then guesses widget type from the
parameter's **name**: a name ending `_key`/`_token`/`password`/`connection_string` → `secret`;
`headers` or a name ending `_params`/`_data`/`_config` → `json`; otherwise `typeof` the
example value.

**This is precisely what decision §3 and §4 forbid** — presentation computed in the browser
from ambient guesswork, rather than derived server-side from the type. This app arrived at it
independently, for the same reason DashiBoard did: the backend did not send enough.

### 4d. The incident that argues the spec's case

[toolRegistry.ts:5-8](src/lib/toolRegistry.ts#L5-L8) records what the client-side approach
cost:

> *"It previously shipped a 15-entry static mock as a fallback, which — because the route
> returns an object and the client mapped it as an array — silently became the catalogue the
> whole UI ran on, against 65 registered tools. Do not reintroduce a fallback list."*

A client-side stand-in for a backend fact silently replaced the backend fact, and the UI
looked correct while offering less than a quarter of the real options. The fix removed the
fallback entirely and made an empty palette a visible failure
([:130-134](src/lib/toolRegistry.ts#L130-L134)).

A second incident is recorded two lines further: the backend emits lowercase security tiers,
`SecurityTier` is uppercase, and *"this mismatch stayed invisible while the mock stood in for
the live list"* ([:100-102](src/lib/toolRegistry.ts#L100-L102)).

**Assessment, honestly:** this repository has no schema-driven form layer to offer the
refactor, and its one attempt at approximating one produced a documented silent-wrong-data
failure. That is not a reason to be embarrassed about the code — the mitigations are careful
and well-argued — but it is strong, independent, in-repo evidence for decision §3's central
choice. **I agree with decision §3 and would cite this file when defending it.**

---

## 5. Nesting and server-supplied enums

### 5a. Plainly: none exists

**There is no recursive form renderer, no discriminated-union renderer, and no example of
nested or discriminated-union parameters rendered as structured UI anywhere in this
application.** I looked for one and there is nothing to show.

Decision §3's requirement — a scalar field is a leaf; a field whose type is an abstract union
is a type-selector plus the selected variant's own component inline, three or four levels deep
— **has no precedent here whatsoever.**

### 5b. How deep the app actually goes

- **One level, hand-written per field.** `llm_config`
  ([NodeEditorDialog.tsx:39-45](src/components/NodeEditorDialog.tsx#L39-L45)) is a nested
  object rendered field-by-field with a bespoke `updateLLM` setter
  ([:173-174](src/components/NodeEditorDialog.tsx#L173-L174)). Not derived, not reusable —
  written out once for this one object.
- **Two levels degrade to a textarea.** A tool's `params`
  ([:31](src/components/NodeEditorDialog.tsx#L31)) is `Record<string, unknown>`; each entry
  renders through `paramInput`, and anything object-shaped becomes a JSON textarea
  ([:135-143](src/components/NodeEditorDialog.tsx#L135-L143)).
- **The explicit escape hatch.** `model_extra_params`
  ([:44](src/components/NodeEditorDialog.tsx#L44)) is `Record<string, unknown>` — where the
  model stops and free-form JSON begins.

The one structure resembling a variant selector is `available_routes` / `RichRoute`
([:34-37](src/components/NodeEditorDialog.tsx#L34-L37)) — but that is a list of `{name,
description}` pairs, a repeater, not a type-discriminated union with per-variant fields.

### 5c. Server-supplied enums: the same anti-pattern again

Two examples, both computing options client-side:

**Hardcoded.** `PROVIDERS` ([NodeEditorDialog.tsx:100](src/components/NodeEditorDialog.tsx#L100)):

```ts
const PROVIDERS = ["bedrock_converse", "openai", "anthropic", "ollama", "azure_openai", "vertexai"];
```

A closed set of backend-meaningful values, pinned in the client. Exactly what decision §3's
"baked server-side" removes.

**Computed from sibling state.** `buildFromSuggestions`
([:82-96](src/components/NodeEditorDialog.tsx#L82-L96)) walks every *other* node in the graph
and derives valid `from` references as `nodeId.outputName`, seeded with `$initial_inputs`.

That second one deserves emphasis: **it is the direct structural analogue of DashiBoard's
`frontend/src/cards/card.jsx:8-27`**, which computes available column names from other cards'
declared outputs. Two codebases, no shared code, the same ambient-scope computation — and
decision §3 removes both by injecting the enum into `$defs` server-side. The convergence is
evidence that the pull toward client-side enum computation is structural, and that the fix has
to be structural too.

### 5d. What this means for the design

**It costs nothing, under the iframe recommendation.** The recursive renderer belongs to
whoever owns the card UI, and decision §1 puts that in DashiBoard. This app does not need to
build it, and its absence here is not an obstacle.

**It would cost a great deal under a component embed.** The renderer would have to be built in
React, in a repository with no form abstraction, no validation layer and no recursive-rendering
precedent — while `DashiboardPage` is simultaneously replaced. I would rate that the single
largest hidden cost of option (ii), larger than the peer-dependency and Tailwind problems in
section 2.

**One thing this app should adopt regardless:** if DashiBoard's Julia backend grows a proper
per-type schema surface, AgentGraph's `/v1/graphs/schema` is the same idea for node
configuration, and this app should start consuming it and delete `inferKind` and `PROVIDERS`.
Out of scope for this refactor, but it is the same lesson, and the two repositories would then
share one pattern instead of two hand-rolled approximations. Section 9's type is written to
serve both.

---

## 6. Graph rendering

### 6a. Confirmed: no graph library

**Confirmed.** Checked programmatically against [package.json](package.json): no `reactflow`,
`@xyflow/*`, `d3*`, `dagre`, `elkjs`, `cytoscape`, `@viz-js/viz`, `mermaid`, `graphlib`,
`vis-network` or `sigma`, in dependencies or devDependencies. `recharts` (`^2.15.4`) is
present but is a charting library — it draws `chart.tsx`
([components/ui/chart.tsx](src/components/ui/chart.tsx)), not graphs.

Everything graph-shaped is hand-rolled SVG.

### 6b. The three renderers

**1. `GraphMinimap`** ([GraphMinimap.tsx](src/components/GraphMinimap.tsx)) — 142 lines.
Layout ([:41-66](src/components/GraphMinimap.tsx#L41-L66)) buckets nodes by their `layer`
field, sorts the buckets, and places node *i* of *n* at `x = (W/(n+1))·(i+1)`, `y` by layer
index. Edges are straight `<line>` elements
([:85-95](src/components/GraphMinimap.tsx#L85-L95)). It **consumes** `layer`; it does not
compute it. Hardcoded hex throughout (section 3a).

**2. `ArtifactLineageGraph`** ([ArtifactLineageGraph.tsx](src/components/ArtifactLineageGraph.tsx))
— 193 lines, self-described at [:5-10](src/components/ArtifactLineageGraph.tsx#L5-L10) as a
*"structural clone of `GraphMinimap.tsx`'s idiom"* collapsed to three fixed rows
(parents/self/children). Its one advance is width-aware placement: `nodeHalfWidth`
([:53-58](src/components/ArtifactLineageGraph.tsx#L53-L58)) uses `estimateTextWidth`
([artifactFacts.ts:68](src/lib/artifactFacts.ts#L68)) so a long `alias@version` claims more
room than a short label, described as *"layout-grade, not pixel-exact"*
([:51-52](src/components/ArtifactLineageGraph.tsx#L51-L52)).

**3. `GraphBuilderPage`'s main canvas — and this is the one that matters.**

### 6c. Automatic DAG layout already exists here

`computeTopologicalLayers`
([GraphBuilderPage.tsx:254-311](src/pages/GraphBuilderPage.tsx#L254-L311)) is Kahn's
topological BFS assigning each node a layer index from the edges alone. It is more careful
than its 57 lines suggest, and every subtlety is a scar:

- **Longest-path layering**, not first-visit: `layers.set(next, Math.max(layers.get(next) ?? 0,
  candidate))` ([:295](src/pages/GraphBuilderPage.tsx#L295)) — so a node sits below *all* its
  predecessors.
- **Back-edge exclusion.** The tool-loop return edge `<agent>__tools → <agent>` is a real
  runtime edge that would give its agent a spurious predecessor
  ([:246-252](src/pages/GraphBuilderPage.tsx#L246-L252)); skipped at
  [:266](src/pages/GraphBuilderPage.tsx#L266).
- **Self-loop exclusion** ([:267](src/pages/GraphBuilderPage.tsx#L267)).
- **Cycle fallback.** With no in-degree-0 seed, it seeds from the least-constrained nodes
  rather than dropping everything onto layer 0 — the previous behaviour *"render[ed] the whole
  graph as one parallel row"* ([:272-281](src/pages/GraphBuilderPage.tsx#L272-L281)).
- **Termination guard.** A `seen` set ([:289](src/pages/GraphBuilderPage.tsx#L289)) restores
  Kahn's dequeue-once invariant that the fallback broke — without it, re-seeded cycles drove
  in-degrees negative and *"froze the tab on cyclic graphs"*
  ([:284-288](src/pages/GraphBuilderPage.tsx#L284-L288)).

### 6d. A correction to the launch prompt's framing

The launch prompt groups `layer` with `PipelineConnection` and connection-drawing as things
that "have no counterpart". **For `DashiboardPage` that is right. For this repository as a
whole it is not, and the distinction is worth having:**

| | `DashiboardPage` | `GraphBuilderPage` |
|---|---|---|
| Origin of `layer` | User-assigned; `maxLayer + 1` on add ([:263-270](src/pages/DashiboardPage.tsx#L263-L270)), then dragged ([:327-330](src/pages/DashiboardPage.tsx#L327-L330), [:549](src/pages/DashiboardPage.tsx#L549)) | **Computed** from inferred edges ([:349-352](src/pages/GraphBuilderPage.tsx#L349-L352), [:375](src/pages/GraphBuilderPage.tsx#L375)) |
| Stored? | Yes, in page state | **No.** Derived on every load |
| Edges | **User-drawn** ([:291-296](src/pages/DashiboardPage.tsx#L291-L296)) | **Inferred** by the backend, read from `GraphDetail` |
| Verdict | **Filler** | **Already what decision §5 asks for** |

And `GraphBuilderPage` has already internalised the consequence that follows: because the
canvas is a derived view, it refuses to save. *"No Save here. The builder is a VIEW of the
resolved topology; it cannot re-serialize the authored document without dropping what the
canvas does not model"* ([:1031-1035](src/pages/GraphBuilderPage.tsx#L1031-L1035)).

So the host's expectations are **not** uniformly hostile to decision §5. Its serious page
already runs on inferred edges, computed layout and no stored positions. Only the mock does
otherwise. That is a better starting position than the prompt assumes, and it means the
"auto-laid-out DAG with no stored positions" model will not feel alien to anyone working in
this repository.

### 6e. Could this app render an auto-laid-out DAG?

Yes, three ways, in increasing cost:

1. **Reuse what exists.** `computeTopologicalLayers` + the `GraphMinimap` placement idiom
   would render a layered DAG today, with no new dependency. Its limits: no crossing
   minimisation, within-layer order is insertion order, edges are straight lines with no
   routing, no port or edge-label placement, and no bipartite (card + variable) rendering of
   the kind `Pipelines.graphviz` emits. Adequate for tens of nodes; visibly poor beyond that.

2. **Add a layout engine.** `elkjs` (layered algorithm, ~1 MB, runs in a worker) or `dagre`
   (~200 KB, unmaintained but stable and sufficient for layered DAGs). Either gives crossing
   reduction and edge routing while keeping SVG rendering under this app's control.

3. **Match DashiBoard: `@viz-js/viz`.** Since DashiBoard already emits Graphviz DOT and
   renders it with `@viz-js/viz`, this app could consume the same DOT and produce a pixel-
   identical graph. That is the only option giving *one* rendering with no second
   implementation to keep in step — a real advantage, given that §5 requires the DOT output to
   change from bipartite to the node+group vocabulary anyway, and a second renderer would have
   to track that change.

**Under the iframe recommendation, this is moot for `/dashiboard`:** DashiBoard renders its
own DOT inside the frame, and this app adds no graph dependency at all. It matters only if the
lead session chooses a component embed — in which case **option 3**, so the DOT-to-picture step
exists once.

---

## 7. Backend coupling and the services API

### 7a. `src/lib/api.ts`

2,889 lines, one module, the app's entire backend surface. Header at
[:1-6](src/lib/api.ts#L1-L6).

**Configuration is build-time.**

```ts
const BASE_URL = import.meta.env.VITE_METAGRAPH_API_URL as string | undefined;  // :249
const API_KEY  = import.meta.env.VITE_METAGRAPH_API_KEY as string | undefined;  // :250
export const isLiveMode = Boolean(BASE_URL);                                    // :252
```

`isLiveMode` is the app-wide mock/live switch, branched on throughout (e.g.
[:876](src/lib/api.ts#L876), [:883](src/lib/api.ts#L883),
[:980](src/lib/api.ts#L980)). The mode is logged at module load
([:254](src/lib/api.ts#L254)). [.env](.env) sets `VITE_METAGRAPH_API_URL=http://127.0.0.1:8000/v1`
and `VITE_APP_MODE=full`, and **does not set the API key** — so no `Authorization` header is
sent in the default local setup.

`VITE_APP_MODE` is separate, read in [appMode.ts:8](src/lib/appMode.ts#L8); `lite` ships a
restricted build ([:4-6](src/lib/appMode.ts#L4-L6)).

**Request machinery** — `requestWith`
([:581-622](src/lib/api.ts#L581-L622)) is the shared core:

- Auth header only when a key exists ([:604](src/lib/api.ts#L604)); JSON content-type unless
  the body is `FormData`, which must set its own boundary
  ([:597-603](src/lib/api.ts#L597-L603)).
- **Only GET/HEAD are retried** ([:591-592](src/lib/api.ts#L591-L592)), argued at
  [:588-590](src/lib/api.ts#L588-L590): replaying a POST could close a workspace twice or
  register a second graph version — *"a silent double-write"*.
- Transient = 502/503/504, or a fetch rejection meaning the request never reached a decision;
  *"A 4xx is a verdict and must never be retried"*
  ([:569-574](src/lib/api.ts#L569-L574)).
- Backoff `[400, 800, 1600, 3200, 3200] ms` ([:565](src/lib/api.ts#L565)), sized against a
  measured `uvicorn --reload` outage of ~8 s ([:561-564](src/lib/api.ts#L561-L564)), jittered
  so a page full of components does not retry in lockstep
  ([:617-618](src/lib/api.ts#L617-L618)).

Three wrappers: `request` (JSON, [:624-626](src/lib/api.ts#L624-L626)), `requestBlob`
([:631-633](src/lib/api.ts#L631-L633)) and `requestNoContent` for the 204 on
`DELETE .../connection` ([:643-656](src/lib/api.ts#L643-L656)).

**Errors** — `ApiError(status, message)` ([:537-541](src/lib/api.ts#L537-L541)) and
`apiErrorDetail` ([:548-559](src/lib/api.ts#L548-L559)), which unwraps FastAPI's
`{"detail": ...}` because *"showing that raw to a user leaks the envelope"*
([:543-547](src/lib/api.ts#L543-L547)). The house rule is to surface backend messages
verbatim — see [RegisterArtifactDialog.tsx:136-138](src/components/RegisterArtifactDialog.tsx#L136-L138):
*"Verbatim: the 422 … the 413, register-path's 404 naming the path, and 503 naming the
registry outage are the UX — paraphrasing here would throw that away."*

**TanStack Query key conventions: none.** See 4b — the library is mounted but unused.

**Vite dev proxy: none.** [vite.config.ts](vite.config.ts) sets only `server.host`,
`server.port` and `server.hmr` ([:8-14](vite.config.ts#L8-L14)); there is no `server.proxy`.
The browser calls `http://127.0.0.1:8000/v1` cross-origin directly, so **AgentGraph must
already serve CORS headers for the dev origin** — meaning cross-origin API access is a solved,
in-production condition here, not a new risk introduced by any embedding choice.

### 7b. The port collision — flagging this hard

**The Vite dev server listens on port 8080** ([vite.config.ts:10](vite.config.ts#L10)). Per
`00-dashiboard-context.md` and `02-stack.md`, **both** the DashiBoard server and
ExperimentTracking default to 8080.

This is not hypothetical. The app already ships an error hint for exactly this collision:

> *"Something else answers at this URL — likely the wrong port (the UI dev server lives on
> :8080)."* — [ConnectionPanel.tsx:97](src/components/ConnectionPanel.tsx#L97)

triggered when a health probe's error contains `"not JSON"`
([:80](src/components/ConnectionPanel.tsx#L80)) — i.e. when the Julia client got this app's
HTML back. The committed launch guidance dodges it by using port **18632**
([ConnectionPanel.tsx:19-28](src/components/ConnectionPanel.tsx#L19-L28)).

Under the iframe recommendation this gets worse, because a misconfigured URL would frame *this
app inside itself*. **Recommendations:** move the Vite dev server off 8080 (5173, Vite's
default, is free); pick a non-8080 default for whichever Julia server serves the UI; and have
the embed refuse to frame a URL whose origin equals `window.location.origin` — cheap, and it
turns an infinite-recursion puzzle into an error message.

### 7c. `/v1/services` — fully consumed, and it is the answer to "where does the UI point?"

**Yes, all of it.** `servicesApi` ([api.ts:978-1010](src/lib/api.ts#L978-L1010)):

| Call | Route | Line |
|---|---|---|
| `list()` | `GET /services` | [:979-982](src/lib/api.ts#L979-L982) |
| `health(service)` | `GET /services/{s}/health` | [:983-985](src/lib/api.ts#L983-L985) |
| `updateConnection(service, body)` | `PUT /services/{s}/connection` | [:992-1000](src/lib/api.ts#L992-L1000) |
| `resetConnection(service)` | `DELETE /services/{s}/connection` | [:1005-1009](src/lib/api.ts#L1005-L1009) |

**Provenance is modelled and rendered.** `ConnectionSource = "configured" | "env" | "default"`
([api.ts:2626-2628](src/lib/api.ts#L2626-L2628)), carried per field on
`ServiceInfo.connection.source` ([:2640-2646](src/lib/api.ts#L2640-L2646)) and shown with a
`currently:` label naming the layer in force
([ConnectionPanel.tsx:41-52](src/components/ConnectionPanel.tsx#L41-L52)).

**The full `ServiceInfo` shape** ([api.ts:2630-2647](src/lib/api.ts#L2630-L2647)) already
carries `config_inputs: {param, fields, description}[]` — which is where AgentGraph's
`ConfigInput(fields=("nodes","groups","filters"))` surfaces to this app. The UI already
receives the declaration that a node takes a three-key config document.

**Consumers.** `ServicesPage` lists and auto-pings every service through a concurrency-limited
runner, at most 3 in flight ([:24-50](src/pages/ServicesPage.tsx#L24-L50));
`ServiceDetailPage` wires the editor ([:182-186](src/pages/ServiceDetailPage.tsx#L182-L186),
[:77](src/pages/ServiceDetailPage.tsx#L77), [:88-92](src/pages/ServiceDetailPage.tsx#L88-L92));
`ConnectionPanel` renders it, with a shared status vocabulary in
[servicePing.ts](src/lib/servicePing.ts).

**Write discipline is strict, and the reasons are recorded**
([ConnectionPanel.tsx:54-66](src/components/ConnectionPanel.tsx#L54-L66)): only *touched*
fields go in the payload, because *"a form that PATCHes everything it renders writes back
whatever it loaded, so editing the timeout also rewrites the URL — with a value that may be
stale, because the server moved under an open form"* (marked as a confirmed requirement,
product owner 2026-08-27); and a cleared field means "reset to env" and sends `null`, while an
*unusable* one must block the save.

**This app already knows `dashi` is ExperimentTracking.** The launch guidance
([ConnectionPanel.tsx:19-28](src/components/ConnectionPanel.tsx#L19-L28)) starts
`julia --project -e 'using ExperimentTracking, HTTP; …'` and builds a `Registry` — not the
`DashiBoard` package. The distinction `02-stack.md` draws is already reflected in the UI.

**So the answer to "how would an embedded UI learn where to point" is: it already can.**

```ts
const services = await api.services.list();
const dashi = services.find((s) => s.service === "dashi");
const url = dashi?.connection.url;          // may be null on the factory-error branch
```

with `api.services.health("dashi")` as the pre-flight and an existing unreachable state that
renders launch instructions
([ConnectionPanel.tsx:93-110](src/components/ConnectionPanel.tsx#L93-L110)). No new backend
surface is needed for the embed to find its host. This is the second load-bearing reason for
the iframe (section 2c).

### 7d. One place this app fails decision §11's own test

Decision §11 requires that *"the frontend takes its API base address at runtime, never as a
build-time constant."* **This app violates that for its own API today**: `BASE_URL` is baked
at build time ([api.ts:249](src/lib/api.ts#L249)), so a single build cannot be pointed at a
different AgentGraph without a rebuild.

I am not claiming §11 binds this repository — it is written for DashiBoard's frontend. But the
reasoning transfers exactly, the fix is small, and it will be wanted anyway the first time this
app is deployed anywhere other than a developer's laptop. **Recommendation:** fetch a
`/config.json` at startup (or read a `window.__NWP_CONFIG__` injected by the serving host),
falling back to the `VITE_*` values so nothing breaks in dev. Roughly 30 lines around
[api.ts:249-252](src/lib/api.ts#L249-L252), plus making `isLiveMode` resolve after that fetch.

---

## 8. The config artifact lifecycle

### 8a. `dashiboardPipelineId` today — a mock referencing a mock

| Where | What |
|---|---|
| [GraphBuilderPage.tsx:45](src/pages/GraphBuilderPage.tsx#L45) | `dashiboardPipelineId?: string` on `GraphNode` |
| [:436](src/pages/GraphBuilderPage.tsx#L436) | A demo node carries the literal `"pipe-1"` |
| [:627-628](src/pages/GraphBuilderPage.tsx#L627-L628) | `setNodeDashiboard` — local state only |
| [:1234](src/pages/GraphBuilderPage.tsx#L1234), [:1264](src/pages/GraphBuilderPage.tsx#L1264) | Navigate to `/dashiboard?pipeline=${id}` |
| [:1513-1567](src/pages/GraphBuilderPage.tsx#L1513-L1567) | The picker dialog |
| [:1589](src/pages/GraphBuilderPage.tsx#L1589) | Preserved through the node editor as a *"UI-only field"* |

The picker's options come from `useAppData().pipelines`
([:477](src/pages/GraphBuilderPage.tsx#L477)), which is `DEFAULT_PIPELINES` — two hardcoded
entries at [AppDataContext.tsx:96-99](src/contexts/AppDataContext.tsx#L96-L99) that are
**never fetched**. The context says why:

> *"`/v1/pipelines` and `/v1/team` do not exist on the backend yet — firing them on every load
> produced guaranteed 404 noise, and the swallowed failure kept the mock rosters looking
> live."* — [AppDataContext.tsx:176-178](src/contexts/AppDataContext.tsx#L176-L178)

**So `dashiboardPipelineId` is a mock id pointing at a mock list. It is not an artifact
reference, has no connection to `/v1/artifacts`, and is never sent to any backend.** The whole
path must be rebuilt against the artifact registry. `PipelineSummary`
([AppDataContext.tsx:22-28](src/contexts/AppDataContext.tsx#L22-L28)) and its slot in the
context ([:64](src/contexts/AppDataContext.tsx#L64),
[:74](src/contexts/AppDataContext.tsx#L74)) should be deleted, along with the ChatWidget
section that renders it ([ChatWidget.tsx:209-214](src/components/ChatWidget.tsx#L209-L214)).

### 8b. How artifacts actually work

**Listing** — `api.artifacts.list(artifactType?)`
([api.ts:882-885](src/lib/api.ts#L882-L885)) returns **one entry per alias**: the latest valid
row plus a `version_count` ([:879-880](src/lib/api.ts#L879-L880)). It takes the type filter
directly, so `list("structured_data")` is the config catalogue. In mock mode it returns an
honest empty list — *"a fabricated catalog is exactly what this surface must never show"*
([:880-881](src/lib/api.ts#L880-L881)).

Held in a `createBackendRegistryStore` ([artifacts.ts:13-18](src/lib/artifacts.ts#L13-L18))
with `revalidate: "always"`, because *"artifacts are MINTED by using the app (every successful
run registers one), so a warm cache goes stale as a matter of course"*
([:10-12](src/lib/artifacts.ts#L10-L12)). The hook is `useArtifactRegistry()`
([:25-42](src/lib/artifacts.ts#L25-L42)). A `status()` probe
([api.ts:875-878](src/lib/api.ts#L875-L878)) distinguishes "registry not installed" from
"backend down".

**Creating** — two routes, both live-only with no mock branch, *"a fabricated id here would
silently corrupt the catalog"* ([api.ts:889-891](src/lib/api.ts#L889-L891)):

- `upload({file, alias, description, artifactType, artifactFormat?, parentKeys?})` — multipart
  `POST /artifacts` ([:892-911](src/lib/api.ts#L892-L911)).
- `registerPath({path, ...})` — JSON `POST /artifacts/register-path`, for a file already on the
  server's filesystem ([:914-933](src/lib/api.ts#L914-L933)).

Both return `{id, alias, version}` — the backend sequences the version.

**Reading** — `detail(ref)` ([:886-888](src/lib/api.ts#L886-L888)) where `ref` is a uuid **or**
an alias; `content(ref, {offset, limit})` ([:962-969](src/lib/api.ts#L962-L969)) returning a
`kind`-tagged payload ([:2590-2593](src/lib/api.ts#L2590-L2593)); `contentBlob` for images
([:973-975](src/lib/api.ts#L973-L975)).

### 8c. Can a `structured_data` artifact be created from the browser? — Yes, with one blocker

**Creating a new one: yes.** `structured_data` is a valid `RegistryArtifactType`
([api.ts:2488](src/lib/api.ts#L2488)), labelled "Config" in the UI
([artifactFacts.ts:12](src/lib/artifactFacts.ts#L12)). `upload` takes a `File`
([api.ts:893](src/lib/api.ts#L893)), and a `File` can be constructed in memory from a
serialised config — no disk round-trip needed. `.toml` maps to `structured_data` by default
([artifactFacts.ts:328](src/lib/artifactFacts.ts#L328)); `.json` is deliberately excluded as
ambiguous ([:305-308](src/lib/artifactFacts.ts#L305-L308)), so a JSON config needs the type set
explicitly. `structured_data` in `json`/`toml`/`yaml` is text-viewable in-app
([:236-242](src/lib/artifactFacts.ts#L236-L242)).

**Creating a new VERSION: no — and this is the blocker.**
[RegisterArtifactDialog.tsx:53-74](src/components/RegisterArtifactDialog.tsx#L53-L74) documents
it in full. The essential part:

> *"Adding a version was deferred to a flow on the artifact's detail page — which already
> renders the version history — and that flow was never built, so **registering v2 of an
> artifact is currently unreachable from the UI by any route**. Tracked in
> nexus-weaver-pro#8; the block stays until it exists."*

Enforced by `isAliasInUse` ([:74](src/components/RegisterArtifactDialog.tsx#L74)), gating
`canSubmit` ([:86](src/components/RegisterArtifactDialog.tsx#L86)), with a message
([:207-212](src/components/RegisterArtifactDialog.tsx#L207-L212)) carefully worded **not** to
claim aliases are unique — because *"Telling people to 'pick a different name' pushes them to
`name-v2` aliases, which become unrelated artifacts with no shared history and no
latest-valid resolution — the alias layer defeated by its own error message."*

**This is the single hardest blocker in this repository for the embed, and it is independent of
embedding mechanism.** An authoring UI whose entire purpose is iterating on a config document
cannot function if "save my edited pipeline" can only ever mint a *new* alias. Fixing
nexus-weaver-pro#8 is a prerequisite, not a nice-to-have. The backend already supports it —
*"The backend sequences the number itself (`_next_version`), keys uniqueness on (org, team,
alias, version), and returns the assigned version from the create route"*
([:59-62](src/components/RegisterArtifactDialog.tsx#L59-L62)) — so this is UI work only.

### 8d. Is uuid-versus-alias versioning surfaced? — Yes, carefully

- `ArtifactSummary` carries `version` and `version_count`, the latter counting rows of **all**
  statuses — *"sizes the history, not the successes"*
  ([api.ts:2513-2517](src/lib/api.ts#L2513-L2517)).
- `ArtifactDetail.versions` is the recency-ordered sibling list
  ([:2572-2573](src/lib/api.ts#L2572-L2573)).
- `data_lineage` holds *"canonical alias@version lineage refs"*
  ([:2551-2553](src/lib/api.ts#L2551-L2553)).
- `lineageNodeDisplay` ([artifactFacts.ts:45-46](src/lib/artifactFacts.ts#L45-L46)) renders
  `alias@version`, falling back to a shortened uuid for standalone rows.
- `ArtifactLineageRef.version` carries the sharpest note
  ([api.ts:2533-2538](src/lib/api.ts#L2533-L2538)): it is *"the referenced ROW's own version —
  not necessarily the alias's current latest, since a lineage edge names one specific row"*,
  and for an unaliased row it is the uuid, *"not meaningful to display"*.

That is exactly the uuid-pins-a-version / alias-resolves-latest distinction
`ConfigInput` relies on (`02-stack.md`), already modelled and already rendered.

### 8e. `required_columns` already lands somewhere

Decision §2 says the UI annotates what it saves with `content_metadata["required_columns"]`,
computed by calling `validate` before saving. **This app already reads that field and already
implements the same check.**

- `ArtifactFacts.required_columns` and `produced_columns`
  ([api.ts:2502-2503](src/lib/api.ts#L2502-L2503)), served *"VERBATIM from content_metadata —
  never reinterpreted client-side. Absent keys mean 'unknown', never zero"*
  ([:2491-2493](src/lib/api.ts#L2491-L2493)).
- Rendered as `needs` / `produces` on the config card
  ([artifactFacts.ts:199-206](src/lib/artifactFacts.ts#L199-L206)) and in the compact facts
  line as `Needs: …` ([:106-110](src/lib/artifactFacts.ts#L106-L110)).
- `pipelineFitsTable` and `missingColumns`
  ([:286-303](src/lib/artifactFacts.ts#L286-L303)) implement **the same preflight AgentGraph
  runs server-side** (`dashiboard.py:74-84`), returning `"fits" | "missing" | "unknown"` and
  refusing to guess: *"'unknown' when either side lacks facts — advisory only, never a fake
  verdict"* ([:283-285](src/lib/artifactFacts.ts#L283-L285)).

So decision §2's annotation slots straight into machinery that exists: the moment the embedded
UI saves a config carrying `required_columns`, this app can tell a user whether it fits a given
source table **before** they wire it into a node. That is a genuinely useful capability that
comes almost free — and it is a reason to make sure the validate-before-save step in §2 is not
dropped as an optimisation.

**[amended] But the producing side is not a pass-through, and getting it wrong is silent.**
Decision §2 now records that `source_vars` is the union of every `{cols = [...]}` selector — so
a card naming *another card's output* via `cols` lands in it too — and that `id_var` is not
included. `required_columns` is therefore `source_vars − output_vars ∪ {id_var}`, not
`source_vars`.

That matters here specifically because of how this app consumes it. `missingColumns`
([artifactFacts.ts:296-303](src/lib/artifactFacts.ts#L296-L303)) reports every required name
absent from the table's columns. Passing `source_vars` through verbatim would list intermediate
card outputs as required source columns, so `pipelineFitsTable` would return `"missing"` for a
config that fits perfectly — and it would do so *confidently*, because both sides have facts, so
the "unknown" guard at [:290](src/lib/artifactFacts.ts#L290) never fires. A false `"missing"` is
worse than no verdict at all, and it is exactly the class of failure this module's own comments
are written to prevent. Whoever implements the annotation must do the subtraction and the
`id_var` union at the point of production.

### 8f. What the node-side picker needs

To replace [GraphBuilderPage.tsx:1513-1567](src/pages/GraphBuilderPage.tsx#L1513-L1567):

1. **Options from the registry**, not `AppDataContext`: `api.artifacts.list("structured_data")`
   via `useArtifactRegistry()`. Delete `PipelineSummary` and `DEFAULT_PIPELINES`.
2. **A choice of pin.** `alias` (resolves latest) or `alias@version` / uuid (pins). This is a
   real user decision that `ConfigInput` already honours, and today's picker has no vocabulary
   for it.
3. **Fit indication** against the node's `source_artifact`, using
   `pipelineFitsTable`/`missingColumns` — with "unknown" rendered as unknown.
4. **`facts`** — `ArtifactSummary.facts` is a precomputed compact line
   ([api.ts:2523-2527](src/lib/api.ts#L2523-L2527)), so the picker can show what each config
   needs and produces without an N+1 fetch.
5. **An escape hatch to authoring**: "Edit in DashiBoard" → `/dashiboard?pipeline={ref}`,
   replacing today's bare "Open Dashiboard"
   ([:1559-1561](src/pages/GraphBuilderPage.tsx#L1559-L1561)).
6. **Honest empty and error states**, per the house rule
   ([backendRegistryStore.ts:10-19](src/lib/backendRegistryStore.ts#L10-L19)) — today's *"No
   Dashiboard pipelines available. Create one first."*
   ([:1556](src/pages/GraphBuilderPage.tsx#L1556)) cannot distinguish an empty registry from an
   unreachable one, and would state a falsehood in the second case.

### 8g. The handshake I want from an embedded authoring UI

Building on 2d.

**Receiving a config to edit.** The parent resolves `?pipeline=<ref>` (following the durable
`?id=` convention, [GraphBuilderPage.tsx:479-492](src/pages/GraphBuilderPage.tsx#L479-L492)),
fetches it with `api.artifacts.content(ref)` — a `structured_data` config comes back as
`{kind: "text", content, size_bytes}` ([api.ts:2592](src/lib/api.ts#L2592)) — and sends it in
`host:init` as **parsed JSON**, not text. Rationale: the parent already knows the artifact's
`format` from `detail(ref)` and can parse TOML or JSON there; making the frame handle both
serialisations doubles its surface for no benefit. With no `?pipeline=`, `config: null` and the
frame starts empty.

**Handing a saved one back.** The frame emits `embed:save` with the document, plus
`requiredColumns` and `producedColumns` from its own `validate` call — decision §2 already
requires that call, and the frame is the only side that can make it. The **parent** then:

1. serialises to the artifact's existing format (or JSON for a new one);
2. builds a `File` in memory;
3. calls `api.artifacts.upload(...)` — **new version under the existing alias when editing**
   (needs nexus-weaver-pro#8, 8c), new alias when creating;
4. replies `host:saved` with `{configRef, version}` so the frame can clear its dirty flag and
   show the assigned version;
5. on failure replies `host:save-failed` with `apiErrorDetail(err)`
   ([api.ts:548-559](src/lib/api.ts#L548-L559)) — verbatim, per house rule
   ([RegisterArtifactDialog.tsx:136-138](src/components/RegisterArtifactDialog.tsx#L136-L138)).

**Why the parent owns the write.** Three reasons: the AgentGraph API key stays on one side;
DashiBoard needs no knowledge of `/v1/artifacts` and stays runnable standalone as decision §1
requires; and the alias/version decision is a *host registry* concern, not a pipeline-authoring
concern.

**[amended] The annotation needs a route that does not exist.** I asked whether
`POST /artifacts` accepts caller-supplied `content_metadata` or derives `required_columns`
itself. Decision §2 now records the answer as **neither**: no HTTP route writes
`content_metadata` at all. `required_columns` is computed and attached today by
`dashiboard_validate`, an AgentGraph *tool*, running inside the worker process — which a browser
cannot invoke. AgentGraph must expose a route that annotates an artifact.

This adds a step to the save sequence above rather than changing its shape. Between (3) and (4):

> **3b.** call the new annotate route with `{required_columns, produced_columns}`, derived from
> the frame's `source_vars`/`output_vars` per the subtraction in 8e.

Two consequences worth fixing at design time, not after:

- **The write is no longer atomic.** An upload that succeeds followed by an annotate that fails
  leaves a registered config with no facts — which `factsCardModel` renders as an empty config
  card ([artifactFacts.ts:199-206](src/lib/artifactFacts.ts#L199-L206)) and which
  `pipelineFitsTable` correctly reports as `"unknown"`. That degradation is honest, so the
  failure is tolerable, but the parent must surface it rather than reporting a clean save. My
  preference is that the annotate route be *idempotent by artifact id*, so the parent can retry
  it alone without re-uploading.
- **Ordering.** Annotate after upload, since the id does not exist before it. If AgentGraph would
  rather extend `POST /artifacts` to accept `content_metadata` in the same multipart request,
  that is strictly better here — one call, atomic, no partial state — and it is a smaller change
  to this app: one added `form.append` beside the existing ones at
  [api.ts:900-910](src/lib/api.ts#L900-L910). **I would prefer that shape**, and flag it as a
  choice AgentGraph still has.

---

## 9. Recommendation — the shape I want

Given a Julia backend serving JSON Schema per card type, specialised to the current pipeline's
available variables.

### 9a. Principles

1. **Standard JSON Schema, narrowed to a closed profile.** Everything below is valid JSON
   Schema — no invented keywords except two `x-` hints that degrade gracefully. But the
   *profile* is closed: a renderer must be able to `switch` exhaustively and never fall through
   to a JSON textarea. An open dialect is what forces the `paramInput` escape hatch
   ([NodeEditorDialog.tsx:135-143](src/components/NodeEditorDialog.tsx#L135-L143)).

2. **Server-side specialisation is total.** No enum is ever computed in the browser. This kills
   both `PROVIDERS` ([:100](src/components/NodeEditorDialog.tsx#L100)) and
   `buildFromSuggestions` ([:82-96](src/components/NodeEditorDialog.tsx#L82-L96)) in spirit,
   and DashiBoard's `card.jsx:8-27` in fact.

3. **Options carry their own labels.** `oneOf: [{const, title}]` rather than a bare `enum` plus
   a parallel label array — one place to look, no index alignment to get wrong, and it is what
   JSON Schema is for.

4. **Unions discriminate on a literal.** A variant is identified by a `const` on a known
   property, so selecting a type is "swap in this subschema" and never requires the client to
   guess which `oneOf` branch matched.

5. **Order is explicit.** `properties` is a JSON object, and while `JSON.parse` preserves
   string-key insertion order in practice, relying on it to carry *"form order from struct field
   order"* (decision §4) is a silent-failure waiting to happen. An explicit array costs nothing.

6. **Errors are addressed by JSON Pointer.** Decision §3 makes cross-level constraints
   validation-only, so *"the error contract to the UI therefore matters: it is the only place
   some constraints become visible."* A `SchemaValidationError` that cannot point at a field
   cannot be rendered next to one.

### 9b. The type

```ts
/* ─── Envelope ─────────────────────────────────────────────────────────────
 * One response, every card type, already specialised to the pipeline state
 * the request described. Self-contained: every $ref resolves inside $defs.
 */
export interface CardSchemaResponse {
  /** Profile version. Bumped on breaking changes; the client refuses unknown majors. */
  dialect: "dashi/1";
  /** Echo of the specialisation this document was built for — lets the client
   *  detect that it is rendering a form against a stale variable list. */
  context: { nodes: string[]; groups: string[]; cols: string[] };
  /** Keyed by card type — the same keys as CARD_SPECS / the `cards` method. */
  cards: Record<string, CardSchema>;
  /** Filters get the identical treatment (decision §8): derived from the
   *  DataIngestion Filter structs, data-derived bounds already baked in. */
  filters: Record<string, CardSchema>;
  /** Shared variant subschemas, referenced by `$ref: "#/$defs/<key>"`.
   *  Remote refs are not permitted. */
  $defs: Record<string, ObjectSchema>;
}

export interface CardSchema extends ObjectSchema {
  /** Human label for the palette — CARD_SPECS' `label`. */
  title: string;
  description?: string;
}

/* ─── Nodes ────────────────────────────────────────────────────────────────
 * A closed union. `type` plus, for objects, `x-dashi-variant` are enough to
 * pick a renderer with no fall-through.
 */
export type Schema =
  | ObjectSchema
  | MapSchema
  | UnionSchema
  | ArraySchema
  | EnumSchema
  | StringSchema
  | NumberSchema
  | BooleanSchema
  | RefSchema;

/** Present on every node. */
interface Common {
  /** Field label. Decision §4: from the `dashi` tag's `title`. */
  title?: string;
  /** Help text. From `description`. */
  description?: string;
  /** From `fielddefaults`. Absent ≠ null: absent means "no default". */
  default?: unknown;
  /** True when the Julia field is nullable — renders a clear/none affordance
   *  distinct from an empty string. */
  nullable?: boolean;
  /** Advisory only; never hides a field the document already has a value for. */
  readOnly?: boolean;
}

/* ─── The leaf that carries server-supplied enums ──────────────────────────
 * The single most important node. A variable picker, a method choice and a
 * column list are all this shape, differing only in their options — which the
 * SERVER computed. The client never derives options from sibling state.
 */
export interface EnumSchema extends Common {
  type: "string";
  /** Options as label-carrying constants. Order is significant and is the
   *  order rendered. An EMPTY array is meaningful: "no options exist here
   *  yet" (e.g. no upstream node produces columns), and must render as a
   *  disabled control explaining that — never as an empty dropdown, and never
   *  as an excuse to fall back to a free-text input. */
  oneOf: Array<{
    const: string;
    title: string;
    description?: string;
    /** Optional grouping for long lists — e.g. "columns" / "nodes" / "groups".
     *  Purely presentational; absent means one flat list. */
    "x-dashi-group"?: string;
  }>;
}

/* ─── Nesting: the discriminated union ─────────────────────────────────────
 * Decision §3's core requirement. A field whose Julia type is an abstract
 * union becomes THIS: a type-selector plus the selected variant's own schema,
 * rendered inline. The bound is already applied server-side — KMeansMethod
 * sends nine dissimilarities, DBSCANMethod sends six — so the client renders
 * what it is given and never reasons about type bounds.
 */
export interface UnionSchema extends Common {
  /** Property carrying the variant tag. `"type"` matches the document format
   *  (`method = {type = "pca"}`), but naming it keeps the renderer honest. */
  "x-dashi-discriminator": string;
  /** One entry per admissible variant, in the order to offer them. Each is a
   *  self-contained object schema (or a $ref into $defs) whose discriminator
   *  property is a `const`. Nesting is genuine and unbounded: a variant's own
   *  properties may contain further UnionSchemas, three or four deep. */
  oneOf: Array<ObjectSchema | RefSchema>;
}

export interface ObjectSchema extends Common {
  type: "object";
  properties: Record<string, Schema>;
  /** Render order. Explicit rather than relying on key order (9a.5).
   *  Must list exactly the keys of `properties`. */
  "x-dashi-order": string[];
  /** JSON Schema `required`: no default and not nullable (per composite_schema). */
  required?: string[];
  /** Closed by construction — a derived schema has no room for extra keys. */
  additionalProperties: false;
}

/** Only ever points inside this document's own $defs. */
export interface RefSchema { $ref: string; }

/* ─── [amended] The free-form map ──────────────────────────────────────────
 * Added after decision §4 identified the one shape that defeats widget
 * inference: `groups` is `{name: {cols|nodes|groups, through}}` — an object
 * with user-chosen KEYS, which ObjectSchema cannot express, because
 * ObjectSchema enumerates its properties and closes the set.
 *
 * Without this node the profile is not actually closed: a renderer meeting the
 * groups map would have no branch for it and would fall through to a JSON
 * textarea — the exact escape hatch 9a.1 exists to prevent. My original
 * "additionalProperties: false everywhere" was too strong and would have
 * forced that outcome.
 *
 * §4 settles what this dispatches on: the value schema is a `$ref` to a named
 * `$def`, and the renderer keys off that ref to choose the purpose-built
 * picker of §6. That is TYPE IDENTITY, not a widget override — the same thing
 * §3 already says components dispatch on — so §4's no-override rule survives.
 */
export interface MapSchema extends Common {
  type: "object";
  /** Absent, by construction: the keys are the user's. Its absence is what
   *  distinguishes a MapSchema from an ObjectSchema at the type level. */
  properties?: never;
  /** Every value conforms to this. A `$ref` in practice, so the renderer can
   *  dispatch on the ref rather than re-deriving intent from the shape. */
  additionalProperties: Schema;
  /** Constraints on the KEYS — a group name is not free text. */
  propertyNames?: { pattern?: string; minLength?: number };
  minProperties?: number;
  maxProperties?: number;
}

/* ─── Arrays, including the group/variable repeater ────────────────────────
 * Decision §6's repeater is `items` = a UnionSchema over cols/nodes/groups.
 * No new vocabulary is needed for it — it falls out of the two nodes above.
 */
export interface ArraySchema extends Common {
  type: "array";
  items: Schema;
  minItems?: number;
  maxItems?: number;
  uniqueItems?: boolean;
  /** [amended] True when items have no meaningful order, so the UI drops the
   *  drag handles and offers no reordering.
   *
   *  I originally documented this as "order-significant arrays leave it
   *  absent", citing WeightedMinkowski's `weights` as such an array. Decision
   *  §3 has since ruled that shape out, and it is right to: an order
   *  constraint cannot demote to a validation error, because every ordering is
   *  a valid VALUE and one is merely the intended one — there is nothing for
   *  the validator to reject. A schema that renders reordering for `weights`
   *  and relies on validation to catch a wrong order will never catch it.
   *
   *  So this flag is not a rendering hint to set thoughtfully; it is half of
   *  the fix. §12 leaves two ways to design the rule out, and the profile
   *  serves either: mark the GOVERNING field (`inputs`) unordered so no widget
   *  offers a reordering that `weights` would have to track — cheap; or change
   *  the representation so correspondence is explicit rather than positional,
   *  making `weights` a MapSchema keyed by input name — thorough, and it
   *  removes the coupling instead of hiding it. I lean to the second: it is
   *  the only one of the two that survives someone later re-adding
   *  reordering. */
  "x-dashi-unordered"?: boolean;
}

export interface StringSchema extends Common {
  type: "string";
  minLength?: number;
  maxLength?: number;
  pattern?: string;
  /** Widens the control: a multi-line box rather than an input. */
  format?: "textarea" | "date" | "date-time" | "uri";
}

export interface NumberSchema extends Common {
  type: "number" | "integer";
  minimum?: number;
  maximum?: number;
  exclusiveMinimum?: number;
  exclusiveMaximum?: number;
  /** Present ⇒ spinner/slider; absent ⇒ plain numeric input.
   *  `type: "integer"` implies 1 when absent. */
  multipleOf?: number;
}

export interface BooleanSchema extends Common { type: "boolean"; }

/* ─── The error contract ───────────────────────────────────────────────────
 * Decision §3: cross-level constraints are validation, not rendering, so this
 * is the ONLY place some constraints become visible. It must therefore be
 * addressable and complete — one entry per violated constraint, each pointing
 * at a field the form can scroll to and mark.
 */
export interface SchemaValidationError {
  /** RFC 6901 JSON Pointer into the DOCUMENT, e.g.
   *  "/nodes/2/card/method/dissimilarity/weights". Empty string = whole doc. */
  pointer: string;
  /** The Julia-side culprit identifier, for logs and bug reports. */
  culprit: string;
  /** Human-readable, rendered verbatim next to the field — this app's house
   *  rule is that backend messages are the UX, never paraphrased
   *  (RegisterArtifactDialog.tsx:136-138). */
  issue: string;
  /** Other fields implicated in a cross-level constraint, so the UI can mark
   *  BOTH ends of "weights must match inputs in length and order" rather than
   *  blaming the leaf alone. */
  related?: string[];
  severity: "error" | "warning";
}

export interface ValidateResponse {
  valid: boolean;
  errors: SchemaValidationError[];
  /** Decision §2: what the UI stamps onto the artifact's content_metadata,
   *  and what artifactFacts.ts:286-303 already checks a source table against. */
  source_vars: string[];
  output_vars: string[];
}
```

### 9c. Worked example — three real levels

`ClusterCard` → `KMeansMethod` → `WeightedMinkowskiMethod`, abbreviated:

```jsonc
{
  "title": "Cluster", "type": "object", "additionalProperties": false,
  "x-dashi-order": ["inputs", "method"], "required": ["inputs", "method"],
  "properties": {
    "inputs": {
      "type": "array", "title": "Inputs", "x-dashi-unordered": true,
      "items": {                       // ← server-supplied, already specialised
        "type": "string",
        "oneOf": [
          { "const": "PRES",    "title": "PRES",    "x-dashi-group": "columns" },
          { "const": "TEMP",    "title": "TEMP",    "x-dashi-group": "columns" },
          { "const": "rescale", "title": "rescale", "x-dashi-group": "nodes"   }
        ]
      }
    },
    "method": {
      "title": "Method", "x-dashi-discriminator": "type",
      "oneOf": [                        // ← level 2: the type bound, applied server-side
        { "$ref": "#/$defs/kmeans" },
        { "$ref": "#/$defs/dbscan" }
      ]
    }
  },
  "$defs": {
    "kmeans": {
      "type": "object", "title": "K-means", "additionalProperties": false,
      "x-dashi-order": ["type", "k", "dissimilarity"], "required": ["type", "k"],
      "properties": {
        "type": { "type": "string", "oneOf": [{ "const": "kmeans", "title": "K-means" }] },
        "k":    { "type": "integer", "title": "Clusters", "minimum": 1, "default": 3 },
        "dissimilarity": {            // ← level 3: nine options, because KMeansMethod{D <: DissimilarityMethod}
          "title": "Dissimilarity", "x-dashi-discriminator": "type",
          "oneOf": [
            { "$ref": "#/$defs/euclidean" },
            { "$ref": "#/$defs/weighted_minkowski" }
            /* … seven more … */
          ]
        }
      }
    },
    "weighted_minkowski": {
      "type": "object", "title": "Weighted Minkowski", "additionalProperties": false,
      "x-dashi-order": ["type", "p", "weights"], "required": ["type", "p", "weights"],
      "properties": {
        "type":    { "type": "string", "oneOf": [{ "const": "weighted_minkowski", "title": "Weighted Minkowski" }] },
        "p":       { "type": "number", "title": "p", "exclusiveMinimum": 0, "default": 2 },
        "weights": { "type": "array", "title": "Weights", "items": { "type": "number" } }
        /* [amended] The LENGTH half of "same length and order as `inputs`" demotes
           cleanly: a wrong length is an invalid value, and comes back as a
           SchemaValidationError with pointer "…/weights" and
           related: ["/nodes/2/card/inputs"], so the UI marks both ends.

           The ORDER half does NOT demote, and my first draft was wrong to say it
           did. Every ordering is a valid value; only one is intended, and no
           validator can tell which. Decision §3 requires it designed out. Under
           the thorough option that field becomes a MapSchema keyed by input name:

             "weights": { "type": "object",
                          "additionalProperties": { "type": "number" },
                          "propertyNames": { "pattern": "^(PRES|TEMP|rescale)$" } }

           — correspondence explicit, positional coupling gone, and the schema no
           longer encodes a rule it cannot enforce. */
      }
    }
    /* … */
  }
}
```

`DBSCANMethod` would carry the six-entry `dissimilarity` union instead. **The client sees no
type bounds, computes no options, and holds no knowledge of which methods exist** — the whole
point of decision §3, and the exact opposite of `inferKind` and `PROVIDERS`.

### 9d. Why these choices, and the one I am least sure of

- **`oneOf: [{const, title}]` over `enum` + labels.** With `enum` the labels need a parallel
  array, which is an index-alignment bug waiting to happen. This is also what lets an option
  carry `description` and `x-dashi-group` without new vocabulary.
- **An explicit discriminator property over positional `oneOf` matching.** Without it the
  client must validate the value against each branch to discover which one it is — which
  requires a JSON Schema validator in the browser, i.e. re-introducing exactly the client-side
  logic §3 removes. Naming the property makes it a lookup.
- **`$defs` + `$ref` over inlining.** Nine dissimilarity variants inlined under both
  `KMeansMethod` and every other method that admits them multiplies the payload. Refs also
  make it obvious that two cards offering "the same" variant really do offer the same one.
- **[amended] `additionalProperties: false` at every *authored* level** — I first wrote
  "everywhere", which was too strong. A derived schema is complete by construction, and leaving
  it open invites a JSON escape hatch; this app's own experience
  ([NodeEditorDialog.tsx:44](src/components/NodeEditorDialog.tsx#L44),
  [:135-143](src/components/NodeEditorDialog.tsx#L135-L143)) is that an escape hatch, once
  present, absorbs everything the renderer finds hard. But decision §4 identifies one shape
  where open-endedness is the *meaning* rather than a gap — the `groups` map, whose keys are the
  user's — and `MapSchema` above is how the profile expresses it without reopening the hatch:
  the keys are free, the values are a `$ref`, and the renderer dispatches on that ref. "At every
  authored level", as §13 puts it, is the right formulation; mine was not.
- **`x-dashi-order` — the choice I am least sure of.** It duplicates information already in
  `properties` key order and creates a way for the two to disagree. The alternative is to
  document that `properties` key order is significant and rely on it. I chose the explicit
  array because decision §4 makes field order *load-bearing presentation metadata* ("form order
  from struct field order"), and load-bearing things should not ride on a JSON object
  convention. **If the DashiBoard session prefers key order, I will not argue hard** — but then
  say so explicitly in the dialect, so nobody re-sorts `properties` for tidiness and silently
  reorders every form.

Two further notes on the envelope:

- **`context` echoes the specialisation.** Because schemas are specialised server-side, a form
  can be rendering against a variable list that a later edit invalidated. Echoing it lets the
  client notice and refetch, rather than silently offering a column that no longer exists.
  Cheap now; not retrofittable without a breaking change.
- **`filters` sits beside `cards` in one response.** Decision §8 keeps filters a separate
  top-level key in the document while unifying their UI. Splitting them across two endpoints
  would make the client ask twice for one form vocabulary; keeping them in one response with
  separate keys matches the document exactly.

---

## Open questions for the other sessions

**[amended] Answered since first writing.**

- ~~*Can `POST /artifacts` accept caller-supplied `content_metadata`, or does it derive
  `required_columns` itself?*~~ **Neither.** Decision §2 records that no HTTP route writes
  `content_metadata`; the annotation happens today inside an AgentGraph worker tool a browser
  cannot reach. A new route is required. Handled in 8g, where I also argue for extending
  `POST /artifacts` instead, so the write stays atomic.
- ~~*Is a node inspector in the assistant panel wanted?*~~ Not answered, but **correctly
  relocated**: it is now `01-decisions.md` §12, as a project-owner decision rather than a
  question between sessions. That is where it belongs — I could only identify it as the flip
  condition, not settle it.

**AgentGraph session:**
1. Is there a reason `GET /v1/graphs/schema` was never consumed here — did it post-date the
   node editor? (4a)
2. Does `GET /v1/services` guarantee `connection.url` is absolute, and is any origin
   validation applied on write? This app would frame that URL (2f).
3. **[amended]** For the new annotate route: idempotent by artifact id, so a failed annotation
   can be retried without re-uploading? And would you rather extend `POST /artifacts` to take
   `content_metadata` in the same multipart request? I would prefer the latter — one call, no
   partial state, one `form.append` here (8g).

**ExperimentTracking session:**
4. Which port will actually serve the UI? Not 8080, please — see 7b.
5. Will the served UI accept an `/embed` route (or a query flag) that suppresses its own
   standalone chrome, so it can render inside a frame without duplicating this app's header?
6. **[amended]** Decision §10 records that you have no CORS handling at all. Under the iframe
   that is *almost* fine from my side — see the note in 2c — but the `postMessage` handshake
   needs your `/embed` document to be framable, i.e. no `X-Frame-Options: DENY` and no
   restrictive `frame-ancestors` once you add headers. Worth deciding deliberately rather than
   inheriting a default.

**Lead session:**
7. Should `/dashiboard` remain a sidebar destination, or become reachable only from a node's
   artifact picker? (1d)

---

## Work this repository must do, ranked

| # | Work | Blocking? | Why |
|---|---|---|---|
| 1 | Fix nexus-weaver-pro#8 — register a new version under an existing alias | **Yes** | Without it "save my edited pipeline" can only mint a new alias (8c) |
| 2 | Rewrite `DashiboardPage.tsx` as the frame host + handshake | **Yes** | The deliverable (2e) |
| 3 | Replace `PipelineSummary`/`DEFAULT_PIPELINES` with the artifact registry | **Yes** | `dashiboardPipelineId` currently points at a mock (8a, 8f) |
| 4 | Make `?pipeline=` actually read, on the durable `?id=` convention | **Yes** | Written but never read today (2a) |
| 5 | Move the Vite dev server off port 8080 | **Yes** | Collides with both Julia servers; already surfaces as a wrong-port error (7b) |
| 6 | CSP `frame-src` + iframe `sandbox` + strict `postMessage` origin checks | **Yes** | The framed URL is user-editable and server-persisted (2f) |
| 7 | Complete the `.dark` palette — status colours, gradient, shadows | No | Latent today, immediate once tokens are transmitted (3c) |
| 8 | Runtime API base address instead of a build-time constant | No | Decision §11's own test, applied here (7d) |
| 9 | Rewrite `PAGE_CONTEXTS["/dashiboard"]` and drop the ChatWidget pipelines section | No | Both describe the mock (1e) |
| 10 | Consume `/v1/graphs/schema`; delete `inferKind` and `PROVIDERS` | No | Out of scope, but the same lesson (4c, 5c) |
