# UI fragility audit — spec

Findings from a file-by-file pass over `dashiboard-ui/src` on 2026-09-15, merged with the team
leader's review notes, and the decisions taken in the interview that followed. The plan at
`docs/superpowers/plans/2026-09-15-ui-fragility-fixes.md` implements this.

## Standing constraints

- **No commits without review.** Every task lands in the working tree and stops. The reviewer
  commits. (Standing instruction; supersedes the usual "commit per task".)
- **Nothing is measured by inference when it can be measured directly.** The access log
  (`JULIA_DEBUG=DashiBoard`, one line per request with timestamp and counter) is the evidence
  for call counts and bytes; jsdom is the evidence for element identity; a claim that cannot be
  tested is stated as such in the code rather than left implied.
- **SolidJS 2.0.0-rc.4.** `createEffect(compute, effect)` form; store setters take a function;
  signal updates are deferred (tests `await flush()`); `class` takes arrays/objects; no
  `classList`; `JSX.Element` is `Element`.
- **Vitest + jsdom**, `@solidjs/testing-library`. `console.log` is swallowed — write to a file
  when a test needs to report a measurement.
- **`@solidjs/router` 2.0.0-next.19** — `useSearchParams()` returns `[params, setParams]`;
  `createRouter({ routes, history })` with `memoryHistory(initial)` for tests.
- **Julia server**: HTTP 2.6.7; `DashiBoard/test/dashiboard.jl` runs a live server on a free port
  and needs `DASHIBOARD_CACHE=<tmp>` when another server holds the DuckDB lock.

## Findings (audit)

| # | severity | where | finding | evidence |
|---|---|---|---|---|
| A1 | high | `processing.tsx:342,529`; `IRField.tsx:111,188` | `<Show keyed>` on objects that are fresh on every IR refetch. Adding a group remounts every card form and the whole GroupsEditor; open groups fold; picker state is lost. | measured: element identity before/after `addGroup()` |
| A2 | high | `processing.tsx:164` | Probe effect keyed on `JSON.stringify(state)`: whole-document serialise per change, subscribes every leaf, one POST per committed edit, no debounce, no in-flight ordering — a slow reply can overwrite a newer one. | read |
| A3 | high | `IRField.tsx:151,195,243,276` | `id={props.label}` — two cards of one type produce duplicate DOM ids; `<label for>` focuses the wrong card's control. | read |
| A4 | med | `processing.tsx:81` | `get-card-ir` refetched whole (19,152 B) on any vocabulary change; 18,449 B of it (`cards`) is invariant. | measured |
| A5 | med | `processing.tsx:398–410` | `nodeState()` evaluated 7× per card per render, each serialising the card. | read |
| A6 | med | `SelectorField.tsx:74` | `rows()`/`kinds()`/`optionsOf()` recomputed per access, O(values × items) per render, unmemoised. | read |
| A7 | med | `TableView.tsx:100–149` | `options()` yields a fresh `datasource` each recompute → grid cache reset → refetch block 0. Candidate for the extra `fetch-data`. | read |
| A8 | med | `requests.ts:74` | Ignores HTTP status; failures collapse to the caller's default. | read (out of scope for this plan; recorded) |
| A9 | low | `processing.tsx:175,282`; `GroupsEditor.tsx:35` | Findings keyed by index / group name. | known (out of scope) |
| A10 | low | `FilePicker.tsx:14` | I/O inside `createMemo`. Measured not to double-fetch. | measured (out of scope) |

## Team leader's notes, and what was decided

| note | decision |
|---|---|
| Responsiveness; see exactly which Julia calls happen | The access log exists (`LoggingMiddleware`, uncommitted). A1, A2, A4, A7 are the causes. Re-measure after each. |
| Stores as top-level globals, backed by `sessionStorage` | Stores already are top-level `createStore` globals. Add persistence for **LOADER, FILTERS and CARDS, the confirmation marks, and the last tab**. `PROBE_STORE` is derived and is not persisted (decided 2026-09-15). |
| Tab in the URL via SolidJS Router | `?tab=<section>` as a query param via `useSearchParams`. URL wins; stored last-tab fills a bare `/`. |
| Why remove the split (left = processing, right = visualize)? | **Restore the split.** Left: Load / Filter / Process / The document as tabs. Right: results, always visible, with its own Table / Plots / Graph / Report tabs. As `frontend/` had it (`grid grid-cols-5`, `col-span-2` / `col-span-3`). |
| Why another return value from `dependency_graph`? | **Keep it.** Added in `b04ca7b` (A4) for `graphviz` to label group vertices; the alternative is `collect(String, keys(group_configs))` at `dag.jl:20`. Answer with the reasoning; no code change. |

## Out of scope

A8, A9, A10; the Julia-side A12 (NaN in JSON) and A13 (silent column overwrite) recorded in
`06-design.md`; `initialize_filters` in ExperimentTracking.
