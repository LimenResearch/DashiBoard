# Storage boundaries — design

Why: the post-smoke fixes (PR #170, `sdd/post-smoke`) built a "session" on top of the tab's
`sessionStorage` — a gate ("Recover / Start fresh"), a reset that reloads the page, an overlay for a
table the server no longer holds, filters cleared by a heuristic when a table changes. All of it
grew from one misdiagnosis (2026-09-16): a server restart appeared to keep "too much", when in fact
the browser tab had never been closed. `sessionStorage` was doing its job, and ds-DashiUI's
persistence was already right.

This spec removes what was built on the misdiagnosis and keeps the rest of the branch. Baseline:
PR #170 at `bc03f4a`; the plan implements this on the same branch. No Julia change.

## The line

| state | owner of the truth | the UI |
|---|---|---|
| the **document** — nodes, groups, filters, the confirmation marks on them — and the loaded table's column summaries | the author (document); the server (table), whose DuckDB cache survives restarts | keeps them in the tab (`sessionStorage`, as ds-DashiUI does) so a reload comes back where it was — silently, no gate; closing the tab ends it |
| the open tab | the URL (`?tab=`), which a reload keeps | nothing stored |

Decisions taken in the interview (2026-09-17):

| question | decision |
|---|---|
| A route for "what does the server hold" (`get-loaded`) | **No.** The tab's remembered summaries and the server's persistent cache agree in every ordinary case; the two rare disagreements (a server restarted on a different cache; another tab loading a different file) fail loudly at the first `fetch-data` or run, which is acceptable for a single-user tool. Provenance (which files made `source`) is the saved-documents feature's concern. |
| A "New document" / reset action | **No.** The author removes what they don't want; no general reset. |
| Restoring past sessions | **Out of scope** — a separate, server-side feature. |
| Propagating a deletion to the cards that used it | **Preserved, untouched:** the cascade (`stores.ts`), the live server finding on the card that lost an input, and the missing-chip marker. |
| A filter on a column the loaded table lacks | **Dropped automatically and announced** (amber notice listing the columns, closable) — not kept for the author to remove by hand, and not the branch's silent clear-everything reset. |

## 1. Removed (PR #170's §4 and §3.3)

- `src/session.ts`, `src/session.test.ts`, `src/components/SessionGate.tsx`,
  `src/components/SessionGate.test.tsx`, `src/components/StartOver.tsx`, and their mounts in
  `App.tsx` (the nav keeps `ThemeToggle` alone, as before).
- `TableView`'s `overlayNoRowsTemplate` and the `showNoRowsOverlay()` call on `failCallback`, with
  their comment — the premise (a remembered table the server lacks) is the rare case named above and
  fails loudly on its own.
- `loading.tsx`'s filters-reset-on-column-change and its test. `FILTERS_STORE` is part of the
  document and follows it.
- `dashi.tab`: the `persistedSignal` for the last tab and the `onSettled` redirect in
  `routes/index.tsx`; a bare `/` opens Load. `persistedSignal` itself stays (confirmations use it).
- The `dashi.gate` key is never written again; a stale one is ignored.

Kept exactly as ds-DashiUI had it: `dashi.loader`, `dashi.cards`, `dashi.filters`,
`dashi.confirmations` restored on module load by `persist.ts`; `LOADER_JSON` and the loader
`revision` memo stay (the datasource is rebuilt when the loaded rows change).

## 2. Changed — a filter on a column the loaded table lacks is dropped, and said

Today the Filter tab builds its panels from the loader's summaries, so a filter whose column is not
in the loaded table is invisible and unremovable (check 11: a list filter on `cbwd` survived loading
`pollution_test.parquet`, with no way to clear it but the run's error). A filter that cannot apply
is not worth keeping, and asking the author to remove it by hand is friction. So, whenever the
loader's summaries change (a load answering, or the store restoring on module load), every entry of
`FILTERS_STORE` (numerical or categorical) whose column is not among the summaries is **deleted
from the store** — and the deletion is **announced**: an amber notification in the Filter tab
listing the columns dropped ("Filters removed — not in the loaded table: `cbwd`, `TEMP`"), with an ×
that closes it. The notice is transient UI state (a signal), not persisted. Filters on present
columns are untouched. This replaces the branch's reset-on-column-change heuristic, which cleared
*every* filter whenever the column set differed, silently.

Where: one function in `stores.ts`, `pruneFilters(summaries): string[]` (returns the dropped
column names), called from `loading.tsx` after `setState(reconcile(summaries))` and once on
module load against the restored loader; the notice lives in `filtering.tsx`, fed by a signal
`setDropped(names)` that `Loader` writes through a small exported setter in `stores.ts` (or the
notice reads a `droppedFilters` signal exported from `stores.ts` — one place, either way).

## 3. What stays from PR #170

Everything independent of storage: `severity`; empty-group and overwrite issues; A12 / A13 / A14;
run issues on the cards; the groups editor asking the probe; the cascade (arrays and lone selector
fields); missing chips; the header fold/truncate; the `/probe-pipeline` proxy route; "could not
reach DashiBoard" as a finding; the live-error dot; updater writes for confirmations.

## 4. Tests

- `loading.test.tsx`: the filters-reset test goes; the mount/paging tests stay.
- `stores.test.ts`: `pruneFilters` with summaries lacking `cbwd` deletes the `cbwd` entry, keeps
  the `TEMP` one, returns `['cbwd']`; with all columns present deletes nothing and returns `[]`.
- `loading.test.tsx`: a load whose answer lacks a filtered column → the entry is gone from
  `FILTERS_STORE` afterwards and the dropped names are exposed; a load with the same columns keeps
  the filters (the assertion waits for the load to land, as the previous plan's fix taught).
- `filtering.test.tsx` (new): with dropped names set, the amber notice lists them and its × closes
  it; with none, no notice. Mutation: prune unconditionally → the same-columns case fails.
- `stores.test.ts` / `persist.test.ts`: unchanged (loader, cards, filters, confirmations still
  persist).
- `routes/index.test.tsx`: the last-tab restore tests go; "bare `/` opens Load" and "unknown `?tab=`
  falls back to Load" stay.
- Deleted with their code: `session.test.ts`, `SessionGate.test.tsx`, the `rerun.test.tsx` case
  that relied on the overlay if any (check), the `TableView` overlay lines. Suite count goes down;
  `STRICT_READ_UNTRACKED` stays 0.

## 5. Out of scope

Saved documents. Cross-tab persistence. A `get-loaded` route and file provenance. A reset action.
A message announcing what a deletion cascaded into (the card's state shows it).

## 6. Process

Same worktree and branch (`sdd/post-smoke`, on top of `bc03f4a`), one commit per task, review per
task, whole-branch review, then the owner reviews PR #170 as a whole. The earlier spec
(`2026-09-16-post-smoke-fixes-design.md`) §4 (session gate) and §3.3 (filters reset) are
superseded by this document; a note at the top of that file says so, added in the plan's first
task.
