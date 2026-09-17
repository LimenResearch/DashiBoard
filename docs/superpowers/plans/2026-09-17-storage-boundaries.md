# Storage boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the "session" machinery that PR #170 built on a misdiagnosis (gate, Start over, the TableView overlay, the remembered tab, the filters-reset heuristic), keep ds-DashiUI's silent `sessionStorage` restore, and replace the filters heuristic with "drop a filter whose column the loaded table lacks, and say so".

**Architecture:** Pure UI change on the existing branch. Task 1 deletes the session gate, Start over and the overlay; Task 2 deletes the remembered tab; Task 3 replaces the reset-on-column-change in `loading.tsx` with a `pruneFilters` store function and an amber, closable notice in the Filter tab. No Julia change.

**Tech Stack:** SolidJS 2.0.0-rc.6, Vitest 4 + jsdom, pnpm, ag-grid 32.

**Spec:** `docs/superpowers/specs/2026-09-17-storage-boundaries-design.md`

## Global Constraints

- **Commits:** one per task on `sdd/post-smoke` (on top of `bc03f4a`); nothing pushed by a task. Messages end with a blank line then `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- **UI commands run from `dashiboard-ui/`** with pnpm: `pnpm exec vitest run --reporter=dot`, `pnpm exec tsc --noEmit`, `pnpm run lint` (0 errors), `pnpm run build` — all four after every task. `[STRICT_READ_UNTRACKED]` count stays **0**.
- **Solid 2 rules:** `createEffect(compute, effect)` — every reactive read in `compute`; store setters take a function / `reconcile`; `createMemo` for derived values; tests `await flush()`; reads of stores in JSX/memos only.
- **Persistence kept as ds-DashiUI had it:** `dashi.loader`, `dashi.cards`, `dashi.filters`, `dashi.confirmations` (`persist.ts`, `stores.ts`). No new keys; `dashi.tab` and `dashi.gate` are never written again.
- **Untouched:** everything storage-independent in PR #170 — `severity`, empty-group/overwrite issues, A12/A13/A14, run issues on cards, the groups editor's probe, the cascade, missing chips, the header, the probe proxy route, "could not reach" findings, the live-error dot, updater writes.
- **Tests assert; new assertions are mutation-tested** (change the code so the claim is false → the test fails → restore; paste both).

---

## File map

| file | task | change |
|---|---|---|
| `src/session.ts`, `src/session.test.ts`, `src/components/SessionGate.tsx`, `src/components/SessionGate.test.tsx`, `src/components/StartOver.tsx` | 1 | deleted |
| `src/App.tsx` | 1 | mounts removed; nav back to `ThemeToggle` alone |
| `src/components/TableView.tsx` | 1 | overlay template + `showNoRowsOverlay()` + comment removed |
| `docs/superpowers/specs/2026-09-16-post-smoke-fixes-design.md` | 1 | "superseded" note at the top |
| `src/routes/index.tsx`, `src/routes/index.test.tsx` | 2 | remembered tab removed |
| `src/stores.ts`, `src/stores.test.ts` | 3 | `pruneFilters`, `droppedFilters` signal |
| `src/left-tabs/loading.tsx`, `src/left-tabs/loading.test.tsx` | 3 | reset heuristic → prune call; test replaced |
| `src/left-tabs/filtering.tsx`, `src/left-tabs/filtering.test.tsx` | 3 | the notice |

---

### Task 1: Remove the session gate, Start over and the "no table loaded" overlay

**Files:**
- Delete: `src/session.ts`, `src/session.test.ts`, `src/components/SessionGate.tsx`, `src/components/SessionGate.test.tsx`, `src/components/StartOver.tsx`
- Modify: `src/App.tsx` (imports at lines 5–6; `<SessionGate />` before `<nav>`; the `<span class="flex items-center gap-2">` holding `<StartOver />` and `<ThemeToggle />`)
- Modify: `src/components/TableView.tsx:74-81` (the `!data` branch) and `:122` (`overlayNoRowsTemplate`)
- Modify: `docs/superpowers/specs/2026-09-16-post-smoke-fixes-design.md` (top)

**Interfaces:**
- Produces: nothing imports `../session`; `App.tsx`'s nav renders `<ThemeToggle />` directly as it did at `5e22c82`.

- [ ] **Step 1: Delete the five files**

```bash
git rm src/session.ts src/session.test.ts src/components/SessionGate.tsx src/components/SessionGate.test.tsx src/components/StartOver.tsx
```

- [ ] **Step 2: `App.tsx`** — remove the two imports and the `<SessionGate />` line; replace

```tsx
            <span class="flex items-center gap-2">
              <StartOver />
              <ThemeToggle />
            </span>
```

with `<ThemeToggle />` (as before the branch).

- [ ] **Step 3: `TableView.tsx`** — the `!data` branch becomes

```tsx
          if (!data) {
            params.failCallback();
            return;
          }
```

and the `overlayNoRowsTemplate: …` line in `gridOptions` is removed. Nothing else in the file changes.

- [ ] **Step 4: Run the four checks**

Run: `pnpm exec vitest run --reporter=dot && pnpm exec tsc --noEmit && pnpm run lint && pnpm run build`
Expected: all pass; the suite shrinks by exactly the deleted tests (paste the count); `grep -rn "session\b\|SessionGate\|StartOver" src` returns no code references (comments naming the removal are fine).

- [ ] **Step 5: Supersede the earlier spec** — insert at the top of `docs/superpowers/specs/2026-09-16-post-smoke-fixes-design.md`, after the title:

```markdown
> **Superseded in part (2026-09-17):** §4 (session gate, Start over, the TableView overlay) and
> §3.3 (filters reset on a table change) are withdrawn by
> `2026-09-17-storage-boundaries-design.md`. Everything else stands.
```

- [ ] **Step 6: Commit** — `remove the session gate, Start over and the overlay: sessionStorage was already right`

---

### Task 2: Remove the remembered tab

**Files:**
- Modify: `src/routes/index.tsx:28-41` (the `persistedSignal`, `restored`, `onSettled` redirect, the `createEffect` that stores the slug; imports `persistedSignal`, `createEffect`, `onSettled`, `untrack` if unused afterwards)
- Modify: `src/routes/index.test.tsx:139-176` (the `describe('the remembered tab', …)` block and the comment above it)

**Interfaces:**
- Produces: `Home` reads the section from `?tab=` only; a bare `/` opens Load (the existing tests `opens on Load when the URL says nothing` and `falls back to Load when the URL names a section that does not exist` are the contract).

- [ ] **Step 1: Delete the four tests** — the whole `describe('the remembered tab', …)` block and its two-line lead comment. Drop imports that become unused (check `flush`).

- [ ] **Step 2: Run to verify the state** — `pnpm exec vitest run src/routes/index.test.tsx --reporter=dot`: the remaining tests pass (nothing depended on the stored tab).

- [ ] **Step 3: Remove the code** — in `index.tsx`, delete from the comment `// Read once, on mount, rather than at module scope…` through `createEffect(() => slug(section()), (tab) => { setLastTab(tab); });` (lines ~28–41). Remove `persistedSignal` from the imports and any of `createEffect`, `onSettled`, `untrack` no longer used (run `pnpm exec tsc --noEmit` — unused imports are a lint error, not a type error; `pnpm run lint` must be 0 errors).

- [ ] **Step 4: Run the four checks** — all pass; the suite shrinks by the four deleted tests (paste the count); `grep -rn "dashi.tab" src` is empty.

- [ ] **Step 5: Commit** — `remove the remembered tab: the URL keeps it across a reload`

---

### Task 3: Drop a filter whose column the loaded table lacks, and say so

**Files:**
- Modify: `src/stores.ts` (after `FILTERS_STORE`, ~line 79)
- Modify: `src/left-tabs/loading.tsx` (`loadData`; the `before`/`after` block goes)
- Modify: `src/left-tabs/filtering.tsx` (the notice, above the panels)
- Test: `src/stores.test.ts`, `src/left-tabs/loading.test.tsx` (replace the reset test), `src/left-tabs/filtering.test.tsx`

**Interfaces:**
- Produces: `pruneFilters(summaries: readonly { name: string }[]): string[]` — deletes every `FILTERS_STORE` entry (numerical or categorical) whose column is not among `summaries`, records the dropped names in `droppedFilters`, returns them; **no-op when `summaries` is empty** (no table loaded → nothing can be judged). `droppedFilters: Accessor<string[]>`, `setDroppedFilters: Setter<string[]>` — transient, not persisted.

- [ ] **Step 1: Write the failing tests**

Append to `src/stores.test.ts`:

```ts
describe('pruneFilters', () => {
  it('drops filters on columns the loaded table lacks, keeps the rest, and says which', async () => {
    const s = await import('./stores');
    const [, setFilters] = s.FILTERS_STORE;
    setFilters(() => ({
      numerical: { TEMP: new s.Interval(0, 1), PRES: new s.Interval(0, 1) },
      categorical: { cbwd: new Set(['NW']) },
    }));
    await flush();
    const dropped = s.pruneFilters([{ name: 'TEMP' }, { name: 'No' }]);
    await flush();
    expect(dropped).toEqual(['PRES', 'cbwd']);
    expect(Object.keys(s.FILTERS_STORE[0].numerical)).toEqual(['TEMP']);
    expect(Object.keys(s.FILTERS_STORE[0].categorical)).toEqual([]);
    expect(s.droppedFilters()).toEqual(['PRES', 'cbwd']);
  });

  it('drops nothing when every column is present, and nothing when no table is loaded', async () => {
    const s = await import('./stores');
    const [, setFilters] = s.FILTERS_STORE;
    setFilters(() => ({ numerical: { TEMP: new s.Interval(0, 1) }, categorical: {} }));
    await flush();
    expect(s.pruneFilters([{ name: 'TEMP' }])).toEqual([]);
    // No summaries means no table: a document's filters cannot be judged, so they stay.
    expect(s.pruneFilters([])).toEqual([]);
    await flush();
    expect(Object.keys(s.FILTERS_STORE[0].numerical)).toEqual(['TEMP']);
  });
});
```

Replace `loading.test.tsx`'s `clears the filters when the new table has different columns, and keeps them otherwise` with:

```tsx
  it('drops the filters the new table cannot apply, keeps the others, and reports the dropped', async () => {
    // Check 11 by hand: a list filter on `cbwd` survived loading a table with no `cbwd`, and the
    // run failed on it. A filter that cannot apply is dropped — and said, not silently.
    const [, setLoaderState] = LOADER_STORE;
    const [, setFilters] = FILTERS_STORE;
    setLoaderState(reconcile([num('TEMP'), num('cbwd')]));
    setFilters(reconcile({ numerical: { TEMP: new Interval(0, 1), cbwd: new Interval(0, 1) }, categorical: {} }));
    setDroppedFilters([]);
    await flush();

    // same columns → everything kept, nothing reported
    const served = [{ ...num('TEMP'), summary: { min: 0, max: 42 } }, num('cbwd')];
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? served : ['a.parquet']),
    );
    const { getByText } = render(() => <Loader />);
    fireEvent.click(getByText('choose'));
    await flush();
    fireEvent.click(getByText(/^Load$/));
    await waitFor(() => {
      expect((snapshot(LOADER_STORE[0])[0].summary as { max: number }).max).toBe(42);
    }, { timeout: 1000 });
    expect(Object.keys(snapshot(FILTERS_STORE[0]).numerical)).toEqual(['TEMP', 'cbwd']);
    expect(droppedFilters()).toEqual([]);

    // a table without cbwd → the cbwd filter is dropped and named; TEMP's stays
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? [num('TEMP'), num('No')] : ['a.parquet']),
    );
    await flush();
    fireEvent.click(getByText(/^Load$/));
    await waitFor(() => expect(droppedFilters()).toEqual(['cbwd']), { timeout: 1000 });
    expect(Object.keys(snapshot(FILTERS_STORE[0]).numerical)).toEqual(['TEMP']);
  });
```

(import `droppedFilters`, `setDroppedFilters` from `../stores`.)

Append to `src/left-tabs/filtering.test.tsx`:

```tsx
describe('filters dropped by a load', () => {
  it('are announced, and the notice closes', async () => {
    const { setDroppedFilters } = await import('../stores');
    setDroppedFilters(['cbwd', 'TEMP']);
    await flush();
    const { container } = render(() => <Filters />);
    const notice = container.querySelector('[data-dropped-filters]')!;
    expect(notice).not.toBeNull();
    expect(notice.textContent).toMatch(/not in the loaded table/);
    expect(notice.textContent).toMatch(/cbwd, TEMP/);
    fireEvent.click(notice.querySelector('button[aria-label="dismiss"]')!);
    await flush();
    expect(container.querySelector('[data-dropped-filters]')).toBeNull();
  });

  it('shows nothing when nothing was dropped', async () => {
    const { setDroppedFilters } = await import('../stores');
    setDroppedFilters([]);
    await flush();
    const { container } = render(() => <Filters />);
    expect(container.querySelector('[data-dropped-filters]')).toBeNull();
  });
});
```

(import `flush` from `solid-js`.)

- [ ] **Step 2: Run to verify they fail** — `pruneFilters`/`droppedFilters` do not exist; the loading test's dropped-names assertion fails; no `[data-dropped-filters]`.

- [ ] **Step 3: `stores.ts`** — after `export const FILTERS_STORE …`:

```ts
/**
 * Which filters the last load dropped, by column — for the Filter tab to say so. Transient: a
 * notice, not part of the document.
 */
export const [droppedFilters, setDroppedFilters] = createSignal<string[]>([]);

/**
 * Drop every filter whose column the loaded table lacks, and say which.
 *
 * A filter is authored against a table; load a table without that column and the filter cannot
 * apply — the run fails on it (measured 2026-09-16: a list filter on `cbwd` over
 * `pollution_test.parquet`). Keeping it and asking the author to remove it is friction; clearing
 * every filter whenever the column set changes (the earlier heuristic) threw away the ones that
 * still applied, silently. So: remove exactly the ones that cannot apply, keep the rest, and
 * return the names so the Filter tab can announce them.
 *
 * No summaries means no table is loaded, and a document's filters cannot be judged against
 * nothing — they stay.
 */
export function pruneFilters(summaries: readonly { name: string }[]): string[] {
  if (summaries.length === 0) return [];
  const present = new Set(summaries.map((s) => s.name));
  const dropped: string[] = [];
  const [, setFilters] = FILTERS_STORE;
  setFilters((draft) => {
    for (const kind of ["numerical", "categorical"] as const) {
      for (const name of Object.keys(draft[kind])) {
        if (!present.has(name)) {
          delete draft[kind][name];
          dropped.push(name);
        }
      }
    }
  });
  if (dropped.length > 0) setDroppedFilters(dropped);
  return dropped;
}
```

(`createSignal` is already imported in `stores.ts`.)

- [ ] **Step 4: `loading.tsx`** — delete the `before` block and the `after`/`if (before !== after)` block; `loadData` becomes

```ts
  function loadData() {
    setLoading(true);
    // A Solid 2 store setter takes a *function*, so `.then(setState)` handed it the response array
    // and nothing was stored — every column vocabulary downstream stayed empty with no error.
    // `reconcile` is the idiomatic wholesale replace.
    postRequest("load-files", { files: files() }, [])
      .then((summaries: LoaderStore) => {
        const next = summaries ?? [];
        setState(reconcile(next));
        // Filters are part of the document, but one on a column this table lacks cannot apply:
        // dropped, and announced in the Filter tab. See `pruneFilters`.
        pruneFilters(next);
      })
      .finally(() => setLoading(false));
  }
```

Imports: `pruneFilters` from `../stores`; drop `FILTERS_STORE` from the import if unused.

- [ ] **Step 5: `filtering.tsx`** — above the panels' `<div class="flex flex-row gap-2 pb-4">`:

```tsx
      {/* What the last load dropped: a filter on a column this table does not have cannot apply.
          Said once, here, rather than kept for the author to remove by hand. */}
      <Show when={droppedFilters().length > 0}>
        <div
          data-dropped-filters
          class="mb-3 flex items-start gap-2 rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground"
        >
          <span class="min-w-0 flex-1">
            Filters removed — not in the loaded table: <span class="font-mono">{droppedFilters().join(", ")}</span>
          </span>
          <button
            type="button"
            aria-label="dismiss"
            onClick={() => setDroppedFilters([])}
            class="grid h-4 w-4 shrink-0 place-items-center rounded-sm text-muted-foreground hover:bg-secondary hover:text-foreground"
          >
            ×
          </button>
        </div>
      </Show>
```

Imports: `Show` from `solid-js`; `droppedFilters`, `setDroppedFilters` from `../stores`.

- [ ] **Step 6: Run the four checks** — all pass; the suite grows by four (two `stores`, two `filtering`; the loading test is replaced one-for-one) — paste the count; 0 `STRICT_READ_UNTRACKED`.

- [ ] **Step 7: Mutation-test** — in `pruneFilters`, replace `if (!present.has(name))` with `if (true)`: the "same columns → everything kept" half of the loading test and the "drops nothing when every column is present" test fail. Restore. Remove the `if (summaries.length === 0) return [];` guard: the "nothing when no table is loaded" assertion fails. Restore.

- [ ] **Step 8: Commit** — `filters on columns the loaded table lacks are dropped, and said`

---

## Not a task

- The earlier plan's `LOADER_JSON`/loader `revision` memo stays: the datasource must be rebuilt when the loaded rows change, and the store's serialisation is the cheapest signal of that.
- The `_id` column, saved documents, a `get-loaded` route, a reset action: out of scope (spec §5).

## Self-review

- **Spec coverage.** §1 removals → Task 1 (session, gate, Start over, overlay, superseded note) and Task 2 (`dashi.tab`); "`dashi.gate` never written again" follows from deleting `session.ts` (its only writer). §2 prune-and-announce → Task 3, including the no-table guard the spec implies ("cannot be judged"). §3 untouched by construction — no task touches those files except `stores.ts` (additive) and `loading.tsx`/`filtering.tsx`. §4 tests → Tasks 2 and 3; `stores.test.ts`/`persist.test.ts` unchanged for persistence. The spec's "once on module load against the restored loader" is deliberately **not** implemented: at module load the loader and filters were persisted together by the same session, so they already agree; pruning there would only ever act on the no-table case, which the guard excludes. Recorded here so the reviewer does not chase it.
- **Placeholders.** None; every step has its code or exact command.
- **Type consistency.** `pruneFilters(summaries: readonly { name: string }[]): string[]` — `LoaderStore` entries have `name`, so `pruneFilters(next)` type-checks; `droppedFilters`/`setDroppedFilters` are the same names in `stores.ts`, `loading.test.tsx` and `filtering.tsx`; `data-dropped-filters` and `aria-label="dismiss"` match between component and test.
