# Post-smoke fixes — design

What the 2026-09-16 smoke run of the UI (`.claude/ui-refactor/09-smoke-ledger.md`, entries 13–15,
on `stress.parquet`, 1M rows) turned up, and what to do about it. Folds in the five notes that
were kept in `.superpowers/sdd/todos/` and two older server findings (A12, A13 in
`.claude/ui-refactor/06-design.md`). The plan that implements this is
`docs/superpowers/plans/2026-09-16-post-smoke-fixes.md`.

Baseline: ds-DashiUI @ 2806a54 (the fragility fixes merged). UI: SolidJS 2.0.0-rc.6,
@solidjs/router 2.0.0-next.21, Vitest 4 + jsdom, pnpm. Server: Julia, HTTP.jl 2.6.7, DuckDB.

## Decisions taken (interview, 2026-09-16)

| question | decision |
|---|---|
| Session recovery | **Both**: a gate on load when a previous session exists, and a "Start over" control always available. |
| What "Recover" restores | **The UI only.** No replay of `load-files`; a missing server table shows as the grid's first `fetch-data` failing, which the grid must say plainly. |
| A card referencing a group/node you delete or rename | **Cascade**: the store drops or rewrites the references. |
| A load whose columns differ | **Filters reset; card column references keep-and-mark** (shown as missing, removable). |
| Empty group | **Reported at definition time** by the probe; the UI's own `checkGroup` goes. One authority. |
| A12 (NaN kills the response), A13 (silent overwrite) | **Both in**: A12 → `null`; A13 → a probe-time *warning*. |
| `_id` in the results | **Stays visible.** Not a bug; out of scope. |
| Card header when `name === type` | **Always `type : name`**; fold and truncate do the work. |
| Structure | **One spec, one plan, server tasks first**, same worktree/SDD flow as the fragility work. |

## 1. Server (Julia)

### 1.1 Issues gain `severity`

`Pipelines.issue_report` and the DashiBoard handlers emit issues as today
(`pointer`, `reason`, `found`, `allowed`, `missing`, `related`, `message`) plus
`severity :: "error" | "warning"`. Absent means `"error"`, so existing clients keep working.
Warnings never make `valid` false; they travel in `issues` next to errors. This is the one interface
change; 1.2–1.5 use it.

### 1.2 Empty group — a definition-time error

In `probe_pipeline` (`DashiBoard/src/handlers.jl:166`), before the pipeline is built: for every
group whose selector list is empty, one issue

    {pointer: "/groups/<name>", reason: "empty", severity: "error",
     message: "group `<name>` has no columns"}

and `valid: false`. Only the probe reports it — Confirm on a card calls the probe after
`validate-card`, and the continuous probe runs on every edit, so one place covers every path. The
run (`evaluate_pipeline`) performs the same check before building, so a document sent straight to
it fails with this issue rather than with `UndefKeywordError: keyword argument args not assigned`.

### 1.3 A13 — overwriting an existing column is a warning

After the pipeline is built in the probe, each node's outputs (`get_output_vars` per node; the
Pipeline already computes them in order) are compared against the source columns and every earlier
node's outputs. A collision yields

    {pointer: "/nodes/<i>/card", reason: "overwrites", severity: "warning",
     message: "`<column>` already exists and will be replaced"}

`valid` stays `true`; the run is allowed. Overwriting can be intended, so this is information, not a
rejection.

### 1.4 A14 — a document with no cards runs

`Pipelines/src/group_api/dag.jl:23` `reduce(vcat, view(c.outputs, 1:n_nodes))` gets
`init = String[]` (matching `c.outputs`' element type — check it). A filter-only document produces
the filtered source; an empty document produces the source unchanged. No special "nothing to run"
message: it is a legitimate, cheap run. The probe of an empty document likewise answers `valid: true`. Update on `Pipelines/src/group_api/dag.jl` need to be clearly motivated in docs.

### 1.5 A12 — non-finite floats become `null`

`json_response` (`DashiBoard/src/middleware.jl:116`) maps `NaN`, `Inf` and `-Inf` to `null` before
serialising — a recursive pass over the payload (arrays, dicts, named tuples), or the JSON writer's
own hook if the installed JSON package offers one. A zero-variance z-score comes back as a column of
`null`s in the summaries and the rows, and the run reports success. `allownan = true` is not the
fix: the browser's parser rejects `NaN`.

### 1.6 Run failures carry `issues`

`failure_report` (`handlers.jl:91`) gains the structured form: when the exception is
`Pipelines.SchemaValidationErrors` (or the empty-group check of 1.2), the `pipeline`-kind failure
includes `issues` from `issue_report` next to the prose `errors`. Other `pipeline`-kind faults —
dependency graph, filter SQL, missing column — keep prose only; `issues` is then absent or empty.

### 1.7 Tests

`DashiBoard/test/dashiboard.jl` (live server, own `DASHIBOARD_CACHE`) and `Pipelines/test`:
- probe with `groups = {"empty": []}` and a card reading it → one issue at `/groups/empty`,
  `valid: false`; run of the same → same issue, no `UndefKeywordError`;
- probe of `rescale TEMP suffix = "rescaled"` against a source with `TEMP_rescaled` → one warning
  at `/nodes/0/card`, `valid: true`; the run succeeds;
- `Pipeline([], Dict(), cols)` builds; probe and run of `{filters: [...], nodes: []}` succeed;
- a run whose result holds `NaN` answers 200 with `null` in place; `JSON.parse` in the test reads it;
- run with two incomplete cards → `issues` has two entries with pointers `/nodes/0/card`,
  `/nodes/1/card`, `errors` still present.
Each assertion is mutation-tested (the change reverted → the test fails → restored).

## 2. UI — findings from the server land on the cards

### 2.1 Run failures

`results.tsx`: when `evaluate-pipeline` answers `valid: false` with non-empty `issues`, call
`reportRunIssues(issues)` (new, `stores.ts`), which writes them into `PROBE_STORE.issues`. Cards
then show them exactly as probe findings — same `issuesForNode`, same placement on fields via
`related` pointers. The failure pane's own text becomes "N cards need attention — see the marks on
them" (N = distinct node indices among the issues), with the prose `errors` kept underneath as the
fallback for faults without pointers. The next edit's probe replaces them, as it replaces any probe
result.

### 2.2 Empty groups: one authority

`checkGroup` is deleted from `completeness.ts` (and its tests). `GroupsEditor`'s Confirm, which
today computes `checkGroup` locally into `unfinished`, instead asks the probe (the same
`askProbe(document)` the card Confirm uses, exported from where it lives or moved to `stores.ts`)
and keeps the issues whose `pointer` is `/groups/<name>`. The continuous probe's issues for a group
render live the same way. The warning panel and the orange dot are unchanged.

### 2.3 Warnings

`ProbeIssue` gains `severity?: "error" | "warning"`. A finding with `severity: "warning"` renders in
the warning style (amber border/background, as the groups editor's panel does) instead of the error
style, on the same field. Confirm still marks the card confirmed; the state dot stays green. A13's
"already exists and will be replaced" is the first user.

### 2.4 Tests

`results.test.tsx`: a failed run with two issues puts a mark on each of two cards and the pane names
the count. `processing.test.tsx`: a warning issue renders amber and Confirm succeeds. `GroupsEditor`
test: an empty group shows the probe's message after Confirm; `checkGroup` no longer exists.

## 3. UI — references that can dangle

### 3.1 Cascade on the user's own edits (`stores.ts`)

`removeGroup(name)` and `removeNode(index)` also drop every selector item that names the thing —
`{groups: name}`, `{nodes: id}`, and any item whose `through` chain contains the id — from every
card and from every other group. `renameGroup(from, to)` and `setNodeId(index, id)` rewrite them.
One structural walk: any array of objects carrying `cols` / `groups` / `nodes` / `through` keys is a
selector, so no IR lookup is needed and future selector-shaped fields are covered. A selector item
left with no values is removed. Confirmation marks are not touched: a card whose inputs changed
reads as unconfirmed by its content signature, which is right.

### 3.2 Keep-and-mark for what the cascade cannot know (`SelectorField.tsx`)

A row whose value is not in the current vocabulary (a column the loaded table lacks; a reference in
an imported document) renders its chip in a "missing" style with an × control; the picker does not
list it, since there is nothing to switch. Removing it writes the document like any other change.
Nothing is silently dropped and nothing is silently kept.

### 3.3 Filters reset on a table change (`loading.tsx`)

After a successful load, if the set of column *names* differs from the previous `LOADER_STORE`'s,
`FILTERS_STORE` is reset to `{numerical: {}, categorical: {}}`. Same names keep the filters
(`stress.csv` → `stress.parquet`).

### 3.4 Not designed around

The observed disappearance of `{cols: "TEMP"}` after a load (ledger entry 15, check 11) is not
reproduced in jsdom by the store change alone. With 3.2 in place a missing column is visible; if it
still vanishes, that becomes its own task with a real-browser repro.

### 3.5 Tests

`stores.test.ts`: group remove/rename, node remove/rename, and a `through` chain — each asserts the
document after the cascade, including a group referencing another group. `SelectorField.test.tsx`:
a value outside the vocabulary renders as missing; its × writes the item out. `loading.test.tsx`: a
load with different names clears the filters; same names keeps them.

## 4. UI — session gate and Start over

### 4.1 `session.ts` (new, beside `persist.ts`)

- `hasPreviousSession()` — true when the restored document is non-empty (any loaded columns, groups
  or cards) and `sessionStorage["dashi.gate"] !== "answered"`.
- `recoverSession()` — sets that flag.
- `resetSession()` — removes every `sessionStorage` key starting with `dashi.` and calls
  `location.reload()`, so the stores come back empty through the one path they already have. No
  lazy stores, no second code path.

### 4.2 The gate (`App.tsx`, above the router outlet)

When `hasPreviousSession()`, a small panel renders over the document: "A previous session is here:
*N columns loaded · G groups · C cards*. Recover it, or start fresh?" with two buttons. The document
underneath is inert until one is pressed. Recover → `recoverSession()`; Start fresh →
`resetSession()`.

### 4.3 Start over (nav, next to the theme toggle)

Always visible. A native `confirm("Discard the loaded table, filters and cards?")`, then
`resetSession()`. The same function as the gate's second button.

### 4.4 Behaviour to know

`sessionStorage` is per tab and survives reloads, so "a previous session" can only mean *this tab
reloaded* — the restart case that prompted this. The flag makes the gate ask once per tab
lifetime; F5 while working stays one keystroke. A new tab has no storage, hence no gate. Recovery
restores the UI only (decision above): if the server no longer holds the table, the grid's first
`fetch-data` fails — `TableView` shows a one-line message in the grid's overlay ("DashiBoard has no
table loaded — load a file") instead of an empty grid.

### 4.5 Tests

`session.test.ts`: `hasPreviousSession` for empty / non-empty / answered; `resetSession` removes
exactly the `dashi.*` keys and leaves others (reload stubbed). `App` test: gate shown for a
non-empty restored document, gone after Recover; Start over asks before clearing.

## 5. UI — the card header

`Disclosure`'s summary row gets `flex-wrap`; the title (`type : name ●`) is one `min-w-0 truncate`
unit carrying the full text in `title=`; the action group (Confirm / Remove) is one `shrink-0
ml-auto` unit. Buttons fold to their own line when the title needs the width; the title truncates
with `…` only if it alone exceeds the row. Always `type : name`. The groups editor header shares the
component and gets the same behaviour. jsdom cannot measure layout: the test asserts the classes
and the `title` attribute; the visual check is the owner's, at the left pane's width.

## 6. Out of scope

`_id` in the results (kept, by decision). `FilePicker` fetching the file list once at mount (A10 —
a new file needs a reload to appear). `loadIR` having no in-flight sequence guard. Cross-tab
persistence (`localStorage`).

## 7. Process

Worktree branch from ds-DashiUI, one commit per task on the side branch, TDD with mutation evidence
per task, server tasks first (§1) then UI (§2–§5), whole-branch review, then a PR the owner
reviews. Julia suites run with their own `DASHIBOARD_CACHE`. The five files in
`.superpowers/sdd/todos/` are superseded by this spec and deleted when it is committed.

**Rule for every change outside `dashiboard-ui/`** (the Julia packages are shared with the team
leader): the functional justification lives in the code — the function's docstring, or a comment
at the change — saying what it does and why it is needed (the observed failure, the case it
serves). Not only in the commit message or this spec. The plan's briefs carry this as a
requirement for §1's tasks and the task reviewer checks it: `init = String[]` gets a comment
naming the card-less document it admits; the empty-group and overwrite issues get their reason in
the docstring of the function that emits them; the `null` mapping in `json_response` gets the
zero-variance case in its docstring.
