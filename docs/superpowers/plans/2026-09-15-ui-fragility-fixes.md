# UI Fragility Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the DashiBoard UI stop rebuilding itself on every vocabulary change, stop over-calling the Julia server, persist the author's work across a reload, put the tab in the URL, and restore the two-pane layout.

**Architecture:** Nine independent tasks, ordered so each later one benefits from the earlier: identity-stable rendering first (or persisted state is torn down on the first refetch), then URL and layout together (same file), then persistence, then the request-volume fixes measured against the access log, then memoisation.

**Tech Stack:** SolidJS 2.0.0-rc.4, `@solidjs/router` 2.0.0-next.19, Vite 8, Vitest 4 + jsdom, ag-grid 32 (infinite row model), Julia 1.12 / HTTP.jl 2.6.7.

**Spec:** `docs/superpowers/specs/2026-09-15-ui-fragility-audit.md`

## Global Constraints

- **Do not commit.** Each task ends by stopping with the changes in the working tree for review. The reviewer commits. Where this plan template would say "Commit", the step says "Stop for review" instead.
- All commands run from `dashiboard-ui/` unless the step says otherwise. Julia commands run from the repository root.
- UI checks after every task: `npx vitest run --reporter=dot`, `npx tsc --noEmit`, `npm run lint` (0 errors), `npm run build`.
- Julia checks when Julia is touched: `DASHIBOARD_CACHE=/tmp/dashi-test julia --project=DashiBoard/test DashiBoard/test/runtests.jl` (the env var avoids the DuckDB lock if a server is running).
- Solid 2 rules: `createEffect(compute, effect)` — every reactive read goes in `compute`; store setters take a function; tests `await flush()` after interactions; `class` takes arrays/objects.
- Tests that measure something print nothing to the console (vitest swallows it); assert instead.
- New assertions are mutation-tested before a task is declared done: change the code so the claim is false, confirm the test fails, restore.

---

## File map

| file | responsibility after this plan |
|---|---|
| `src/components/IRField.tsx` | Recursive renderer. Remounts only when a field's *kind* changes; ids are unique per card. |
| `src/left-tabs/processing.tsx` | Cards section. Probe debounced and sequence-guarded; `cards` half of the IR cached; `nodeState` memoised. |
| `src/routes/index.tsx` | Page shell: two panes, left tabs driven by `?tab=`, results on the right. |
| `src/stores.ts` | The stores, now `sessionStorage`-backed; exports `CARDS_JSON` (one deep serialise shared by persistence and the probe). |
| `src/persist.ts` (new) | `persisted(key, initial, codec?)` — a `createStore` wrapper that saves on change and restores on creation. |
| `src/components/SelectorField.tsx` | Picker. Derived rows/kinds/options memoised. |
| `src/components/TableView.tsx` | Grid. Datasource identity stable across column changes. |
| `DashiBoard/src/handlers.jl` | `get_card_ir` honours `include`. |
| `src/routes/index.test.tsx` | Renders inside a memory-history router. |

---

### Task 1: Remount only when a field's kind changes

**Files:**
- Modify: `src/components/IRField.tsx:108–112` (the `widget` accessor and the `<Show keyed>`), `:188` (variant branch)
- Modify: `src/left-tabs/processing.tsx:342–344` (GroupsEditor), `:526–540` (card IRField)
- Test: `src/left-tabs/processing.test.tsx` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `IRField` remounts a subtree only when `widgetFor(...).kind` changes; `GroupsEditor` and each card's `IRField` survive an IR refetch.

- [ ] **Step 1: Write the failing test**

Create `src/left-tabs/processing.test.tsx`:

```tsx
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import payload from '../fixtures/card-ir.json';
import { importCards, addGroup } from '../stores';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

import { Cards } from './processing';

const CLEAN_PROBE = { valid: true, cols: [], nodes: [], errors: [], issues: [] };

beforeEach(() => {
  postRequest.mockReset();
  postRequest.mockImplementation((page: string) =>
    Promise.resolve(
      page === 'get-card-ir' ? structuredClone(payload)
      : page === 'probe-pipeline' ? CLEAN_PROBE
      : page === 'validate-card' ? { valid: true, issues: [] }
      : [],
    ),
  );
  importCards({
    nodes: [{ id: 'r', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } }],
    groups: { g: [] },
  });
});
afterEach(cleanup);

const irCalls = () => postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir').length;

describe('an IR refetch', () => {
  it('leaves the card form and the groups editor in place', async () => {
    // Adding a group changes the vocabulary, which refetches the IR. The payload is a new object
    // every time, and three `<Show keyed>`s were keyed on it — so every card form and the whole
    // groups editor were torn down and rebuilt, folding open groups and losing picker state.
    // Measured 2026-09-15 by exactly this comparison.
    const { container } = render(() => <Cards />);
    const q = (sel: string) => container.querySelector(sel);
    await waitFor(() => { if (!q('#node-0-rescale-method-variant') && !q('#method-variant')) throw new Error('form not up'); });

    const before = {
      select: q('#method-variant') ?? q('#node-0-rescale-method-variant'),
      groupInput: q('#group-name-g'),
      groupPicker: q('[data-tabs="kinds"]'),
    };
    const groupDetails = [...container.querySelectorAll('details')].find((d) =>
      d.querySelector('#group-name-g'),
    )!;
    groupDetails.open = true;

    const n = irCalls();
    addGroup();
    await waitFor(() => expect(irCalls()).toBe(n + 1));
    await flush();
    await new Promise((r) => setTimeout(r, 30));
    await flush();

    expect(q('#method-variant') ?? q('#node-0-rescale-method-variant')).toBe(before.select);
    expect(q('#group-name-g')).toBe(before.groupInput);
    expect(q('[data-tabs="kinds"]')).toBe(before.groupPicker);
    expect(groupDetails.open).toBe(true);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run src/left-tabs/processing.test.tsx --reporter=dot`
Expected: FAIL — `expected <select …> to be <select …>` (different elements), and `expected false to be true` for `groupDetails.open`.

- [ ] **Step 3: Key `IRField` on the widget kind, not the widget object**

In `src/components/IRField.tsx`, replace the accessor and the outer `Show`:

```tsx
export function IRField(props: IRFieldProps) {
  const widget = (): Widget => widgetFor(props.node, props.defs);

  return (
    // Keyed on the *kind*, not the descriptor. `widgetFor` returns a fresh object on every
    // evaluation, and keying on it remounted this whole subtree whenever `props.defs` changed —
    // which is every IR refetch, i.e. every time a column, group or node name changed anywhere.
    // A field only needs rebuilding when it becomes a different kind of control; everything else
    // it reads reactively through `w()`.
    <Show when={widget().kind} keyed>
      {(kind: Widget["kind"]) => {
        const w = () => widget() as Extract<Widget, { kind: typeof kind }>;
        switch (kind) {
```

Then, inside the `switch`, every read of `w.` becomes `w().`. Do it mechanically and check the count:

```bash
python3 - <<'PY'
import io, re
p = "src/components/IRField.tsx"
s = io.open(p).read()
start = s.index('      {(kind: Widget["kind"]) => {')
head, body = s[:start], s[start:]
n = len(re.findall(r'\bw\.', body))
body = re.sub(r'\bw\.', 'w().', body)
io.open(p, "w").write(head + body)
print("rewrote", n, "reads")
PY
```

Expected: `rewrote 18 reads` (or thereabouts — verify every `w().` compiles).

Two `switch` cases need their `w` typed. Where the compiler complains that `w()` lacks a property (because `Extract` is too loose for the narrowed case), narrow explicitly, e.g. in `case "object":` use `const o = () => widget() as Extract<Widget, { kind: "object" }>;` and read `o().properties`, `o().title`.

- [ ] **Step 4: Un-key the variant branch**

Still in `IRField.tsx`, the variant case:

```tsx
                <Show when={w().objects[chosen()]}>
                  <IRField
                    node={w().objects[chosen()]!}
                    defs={props.defs}
                    label={props.label}
                    inline
                    value={props.value}
                    onChange={(inner) => props.onChange({ ...asRecord(inner), type: chosen() })}
                  />
                </Show>
```

(`keyed` removed; the child reads `node` reactively. When `chosen()` changes to a branch of a different kind, the inner field's own kind-key remounts it — which is the one case a remount is right.)

- [ ] **Step 5: Un-key the two `Show`s in `processing.tsx`**

Replace lines 342–344:

```tsx
      <Show when={payload()}>
        <GroupsEditor defs={payload()!.defs} />
      </Show>
```

Replace lines 526–540:

```tsx
            <Show
              when={payload()?.cards[String(node.card.type)]}
              fallback={<p class="text-muted-foreground">No description for this card type.</p>}
            >
              <IRField
                node={payload()!.cards[String(node.card.type)]}
                defs={defsForNode(index())}
                label={String(node.card.type)}
                value={node.card}
                onChange={(card) => setCard(index(), card as Card)}
              />
            </Show>
```

- [ ] **Step 6: Run the new test and the whole suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit && npm run lint`
Expected: all pass; the new test passes; 0 lint errors.

- [ ] **Step 7: Mutation-test**

Put `keyed` back on the GroupsEditor `Show` only. Run the new test. Expected: FAIL on `#group-name-g`. Restore. Put `keyed` back on `<Show when={widget().kind}>` changed to `when={widget()}`. Expected: FAIL on the select. Restore.

- [ ] **Step 8: Stop for review**

Report: files changed, test output, the two mutation results. Do not commit.

---

### Task 2: Unique DOM ids per card

**Files:**
- Modify: `src/components/IRField.tsx` (props type; every `id=`/`for=`; the recursive calls)
- Modify: `src/left-tabs/processing.tsx:532` (pass `idPrefix`)
- Test: `src/components/IRField.test.tsx`

**Interfaces:**
- Produces: `IRField` accepts `idPrefix?: string`. Every control id is `${idPrefix}-${label}` when a prefix is given, and nested fields prefix with their parent's id. Cards pass `idPrefix={\`node-${index()}\`}`.

- [ ] **Step 1: Write the failing test**

Append to `src/components/IRField.test.tsx`:

```tsx
  it('gives every control an id unique to its card', () => {
    // `id={props.label}` made two cards of one type produce duplicate ids, so a `<label for>`
    // in the second card focused the first card's input.
    const { container } = render(() => (
      <>
        <IRField node={cards.rescale} defs={defs} label="rescale" idPrefix="node-0" value={{}} onChange={() => {}} />
        <IRField node={cards.rescale} defs={defs} label="rescale" idPrefix="node-1" value={{}} onChange={() => {}} />
      </>
    ));
    const ids = [...container.querySelectorAll('[id]')].map((e) => e.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toContain('node-0-rescale-suffix');
    expect(ids).toContain('node-1-rescale-suffix');
    // and each label points at its own card's control
    const label = container.querySelector('label[for="node-1-rescale-suffix"]') as HTMLLabelElement;
    expect(label).not.toBeNull();
    expect(label.control?.id).toBe('node-1-rescale-suffix');
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run src/components/IRField.test.tsx -t "unique to its card"`
Expected: FAIL — duplicate ids (`Set` size less than length) and/or TypeScript error on `idPrefix`.

- [ ] **Step 3: Implement**

In `IRField.tsx`, add to `IRFieldProps`:

```tsx
  /** Prefix for every id below this field, so two cards of one type do not collide. */
  idPrefix?: string;
```

Add after the `widget` accessor:

```tsx
  const id = () => (props.idPrefix ? `${props.idPrefix}-${props.label}` : props.label);
```

Replace every `id={props.label}` with `id={id()}`, every `for={props.label}` with `for={id()}`, and `id={\`${props.label}-variant\`}` / `for={\`${props.label}-variant\`}` with `id={\`${id()}-variant\`}` / `for={\`${id()}-variant\`}`. In the three recursive `<IRField …>` calls (object properties, variant branch, repeater items) add `idPrefix={id()}`. For the repeater item use `idPrefix={\`${id()}-${index()}\`}`.

In `processing.tsx` line 532 add `idPrefix={\`node-${index()}\`}` to the card's `<IRField>`.

- [ ] **Step 4: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit`
Expected: all pass. (The Task 1 test used `#method-variant ?? #node-0-rescale-method-variant`; it still passes.)

- [ ] **Step 5: Mutation-test**

Change `const id = () => props.label;`. Expected: the new test fails on `Set` size. Restore.

- [ ] **Step 6: Stop for review**

---

### Task 3: The active tab lives in the URL

**Files:**
- Modify: `src/routes/index.tsx`
- Modify: `src/routes/index.test.tsx` (render inside a router)
- Modify: `src/left-tabs/results.test.tsx` — no change needed; `Results` has no router dependency.

**Interfaces:**
- Consumes: `useSearchParams` from `@solidjs/router`.
- Produces: `?tab=load|filter|process|document` selects the left section; `SECTIONS` becomes `["Load", "Filter", "Process", "The document"]` (Run leaves the strip in Task 4; here it stays so the test delta is one thing at a time). Test helper `renderHome(url?)`.

- [ ] **Step 1: Write the failing test**

In `src/routes/index.test.tsx`, add imports and a helper near the top (after the mocks, before `describe`):

```tsx
import { createRouter, memoryHistory } from '@solidjs/router';

/** The page inside a router, at `url`. The real app mounts it the same way through `App`. */
function renderHome(url = '/') {
  const TestRouter = createRouter({
    routes: [{ path: '/', component: Home }],
    history: memoryHistory(url),
  });
  return render(() => <TestRouter />);
}
```

Replace every `render(() => <Home />)` in the file with `renderHome()` (sed: `sed -i 's/render(() => <Home \/>)/renderHome()/' src/routes/index.test.tsx`).

Add a test to `describe('the page is a set of tabs'`:

```tsx
  it('takes the open section from the URL, and writes it back', async () => {
    // The tab was a local signal: a reload, a shared link or the browser's back button all lost
    // it. It is now `?tab=`, so all three work, and the URL says what is on screen.
    const { container } = renderHome('/?tab=process');
    await waitFor(() => expect(sectionTabs(container).length).toBeGreaterThan(0));
    expect(onScreen(container)).toEqual(['Process']);

    await openTab(container, 'Filter');
    expect(onScreen(container)).toEqual(['Filter']);
    expect(window.location.search).toBe('');            // memory history: the DOM URL is untouched
    // the router's own location is what moved
    const active = sectionTabs(container).find((t) => t.getAttribute('aria-selected') === 'true');
    expect(active?.textContent).toBe('Filter');
  });

  it('opens on Load when the URL says nothing', async () => {
    const { container } = renderHome('/');
    await waitFor(() => expect(sectionTabs(container).length).toBeGreaterThan(0));
    expect(onScreen(container)).toEqual(['Load']);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/routes/index.test.tsx -t "from the URL"`
Expected: FAIL — `onScreen` is `['Load']` for `?tab=process`.

- [ ] **Step 3: Implement**

In `src/routes/index.tsx`:

```tsx
import { useSearchParams } from "@solidjs/router";
// ...
const SECTIONS = ["Load", "Filter", "Process", "Run", "The document"] as const;
type Section = (typeof SECTIONS)[number];

/** `?tab=` value ↔ section name. Lower-case, one word, so the URL reads well. */
const slug = (s: Section) => s.toLowerCase().replace(/^the /, "");
const fromSlug = (v: string | undefined): Section =>
  SECTIONS.find((s) => slug(s) === v) ?? "Load";

export default function Home() {
  const [params, setParams] = useSearchParams<{ tab?: string }>();
  // The URL is the state. Reading it makes a reload, a shared link and the back button all land
  // on the section they name; writing it with `replace` keeps typing through tabs out of history.
  const section = () => fromSlug(params.tab);
  const setSection = (s: Section) => setParams({ tab: slug(s) }, { replace: true });
```

Remove the `createSignal` for `section`. Everything else in the file reads `section()` and calls `setSection` as before.

- [ ] **Step 4: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit`
Expected: all pass. If a test that clicked tabs now fails because the router did not update synchronously, add `await flush()` after the click in `openTab` (already there).

- [ ] **Step 5: Mutation-test**

Make `fromSlug` return `"Load"` unconditionally. Expected: the `?tab=process` test fails. Restore.

- [ ] **Step 6: Stop for review**

---

### Task 4: Restore the two-pane layout

**Files:**
- Modify: `src/routes/index.tsx`
- Modify: `src/routes/index.test.tsx` (section list; tests that opened `Run`)
- Modify: `src/left-tabs/results.tsx:71–75` (the "Add a card first" hint stays; nothing structural)

**Interfaces:**
- Produces: `SECTIONS = ["Load", "Filter", "Process", "The document"]` on the left; `<Results />` always rendered on the right. `?tab=run` is no longer valid (falls back to Load).

- [ ] **Step 1: Update the tests first**

In `src/routes/index.test.tsx`:

- Change the expected tab list to `['Load', 'Filter', 'Process', 'The document']`.
- Every `await openTab(container, 'Run');` is removed — `Results` is always on screen. The `getByText(/run pipeline/i)` lookups that followed still work.
- In `keeps the sections mounted`, replace `openTab(container, 'Run')` with `openTab(container, 'Filter')`.
- Add:

```tsx
  it('shows results beside the authoring tabs, not behind one', async () => {
    // The old frontend had two panes: what you are building on the left, what it produced on
    // the right. Folding results into a fourth tab meant the thing you ran was hidden by the
    // thing you were editing.
    const { container } = renderHome('/?tab=process');
    await waitFor(() => expect(sectionTabs(container).length).toBeGreaterThan(0));
    expect(container.querySelector('[data-pane="results"]')).not.toBeNull();
    expect(container.querySelector('[data-pane="results"]')!.textContent).toMatch(/run pipeline/i);
    expect(onScreen(container)).toEqual(['Process']);      // left pane unaffected
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/routes/index.test.tsx --reporter=dot`
Expected: FAIL — tab list has 5 entries; `[data-pane="results"]` is null.

- [ ] **Step 3: Implement the layout**

Replace the `return` of `Home` in `src/routes/index.tsx`:

```tsx
  return (
    <main class="grid grid-cols-5 gap-6 px-4 py-2">
      <Title>DashiBoard</Title>

      {/*
        Two panes, as `frontend/` had them: what you are building on the left, what it produced on
        the right. The left is a set of tabs because its stages are steps in one order; the right is
        always visible because a result is the answer to the left, and hiding it behind a tab meant
        the thing you ran was behind the thing you were editing.

        Sections stay mounted and hidden rather than unmounted: Load sets up choices.js, Process
        fetches the card IR, and remounting on each switch would refetch both.
      */}
      <div class="col-span-2 min-w-0">
        <Tabs group="sections" items={SECTIONS} active={section()} onSelect={setSection} size="md" />
        <section class="mt-4" data-section="Load" hidden={section() !== "Load"}><Loader /></section>
        <section data-section="Filter" hidden={section() !== "Filter"}><Filters /></section>
        <section data-section="Process" hidden={section() !== "Process"}><Cards /></section>
        <section data-section="The document" hidden={section() !== "The document"}>
          <pre data-testid="document" class="overflow-x-auto rounded-sm bg-muted p-3 text-control-xs">
            {JSON.stringify(wireDocument(), null, 2)}
          </pre>
        </section>
      </div>

      <div class="col-span-3 min-w-0" data-pane="results">
        <Results />
      </div>
    </main>
  );
```

And `const SECTIONS = ["Load", "Filter", "Process", "The document"] as const;`.

Widen the shell: in the same file the old `max-w-5xl` container is gone (the grid is the container now). Check `App.tsx` — the `<nav>` is unaffected.

- [ ] **Step 4: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit && npm run lint && npm run build`
Expected: all pass; 0 lint errors.

- [ ] **Step 5: Mutation-test**

Remove `data-pane="results"`. Expected: the new test fails. Restore.

- [ ] **Step 6: Stop for review**

---

### Task 5: Persist the stores in sessionStorage

**Files:**
- Create: `src/persist.ts`
- Modify: `src/stores.ts` (LOADER, FILTERS, CARDS and `confirmations`; PROBE stays as is)
- Modify: `src/routes/index.tsx` (last tab)
- Test: `src/persist.test.ts` (new), `src/stores.test.ts` (new)

**Interfaces:**
- Produces:
  - `persisted<T extends object>(key: string, initial: T, codec?: { encode(v: T): unknown; decode(raw: unknown): T }): [Store<T>, SetStoreFunction<T>]` — a `createStore` that restores from `sessionStorage[key]` on creation and writes on every change.
  - `persistedSignal<T>(key: string, initial: T): [Accessor<T>, Setter<T>]`.
  - `export const CARDS_JSON: Accessor<string>` — the serialised document, one deep read shared by persistence and (Task 6) the probe.
  - Storage keys: `dashi.loader`, `dashi.filters`, `dashi.cards`, `dashi.confirmations`, `dashi.tab`. (`PROBE_STORE` is derived and is not persisted.)

- [ ] **Step 1: Write the failing tests**

Create `src/persist.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { flush } from 'solid-js';
import { persisted, persistedSignal } from './persist';

beforeEach(() => sessionStorage.clear());

describe('persisted', () => {
  it('starts from what was saved, and saves what changes', async () => {
    const [a, setA] = persisted('t.store', { n: 0, list: [] as string[] });
    setA((d) => { d.n = 3; d.list.push('x'); });
    await flush();
    expect(JSON.parse(sessionStorage.getItem('t.store')!)).toEqual({ n: 3, list: ['x'] });

    // "reload": a second store under the same key sees the saved value, not `initial`
    const [b] = persisted('t.store', { n: 0, list: [] as string[] });
    expect(b.n).toBe(3);
    expect(b.list).toEqual(['x']);
  });

  it('falls back to initial when storage holds nothing, or garbage', () => {
    sessionStorage.setItem('t.bad', '{not json');
    const [s] = persisted('t.bad', { ok: true });
    expect(s.ok).toBe(true);
  });

  it('uses the codec both ways, for values JSON cannot carry', async () => {
    const codec = {
      encode: (v: { s: Set<string> }) => ({ s: [...v.s] }),
      decode: (raw: unknown) => ({ s: new Set((raw as { s: string[] }).s) }),
    };
    const [a, setA] = persisted('t.set', { s: new Set<string>() }, codec);
    setA((d) => { d.s = new Set(['p', 'q']); });
    await flush();
    const [b] = persisted('t.set', { s: new Set<string>() }, codec);
    expect(b.s).toBeInstanceOf(Set);
    expect([...b.s]).toEqual(['p', 'q']);
  });
});

describe('persistedSignal', () => {
  it('round-trips a plain value', async () => {
    const [a, setA] = persistedSignal('t.sig', 'x');
    setA('y');
    await flush();
    const [b] = persistedSignal('t.sig', 'x');
    expect(b()).toBe('y');
  });
});
```

Create `src/stores.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { flush } from 'solid-js';
import { Interval } from './stores';

beforeEach(() => sessionStorage.clear());

describe('the stores survive a reload', () => {
  it('cards: the document is restored verbatim', async () => {
    // A fresh module instance stands in for a reload: the stores are module-level, so re-importing
    // the module is exactly what a page load does.
    const first = await import('./stores');
    first.importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: { g: [] } });
    await flush();
    expect(JSON.parse(sessionStorage.getItem('dashi.cards')!).nodes[0].id).toBe('r');
  });

  it('filters: Interval and Set come back as themselves', async () => {
    const { FILTERS_STORE, filtersCodec } = await import('./stores');
    const [, set] = FILTERS_STORE;
    set((d) => { d.numerical.TEMP = new Interval(1, 2); d.categorical.cbwd = new Set(['NW']); });
    await flush();
    const raw = JSON.parse(sessionStorage.getItem('dashi.filters')!);
    const back = filtersCodec.decode(raw);
    expect(back.numerical.TEMP).toBeInstanceOf(Interval);
    expect(back.numerical.TEMP!.max).toBe(2);
    expect(back.categorical.cbwd).toBeInstanceOf(Set);
    expect(back.categorical.cbwd!.has('NW')).toBe(true);
  });

  it('confirmations are kept', async () => {
    const { confirmDefinition, isConfirmed } = await import('./stores');
    confirmDefinition('node:0', { type: 'rescale' });
    await flush();
    expect(JSON.parse(sessionStorage.getItem('dashi.confirmations')!)['node:0']).toBeTypeOf('string');
    expect(isConfirmed('node:0', { type: 'rescale' })).toBe(true);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `npx vitest run src/persist.test.ts src/stores.test.ts --reporter=dot`
Expected: FAIL — `./persist` does not exist; `filtersCodec` is not exported.

- [ ] **Step 3: Write `src/persist.ts`**

```ts
import {
  createEffect, createMemo, createRoot, createSignal, createStore,
  type Accessor, type Setter, type Store, type SetStoreFunction,
} from "solid-js";

// sessionStorage-backed state.
//
// The stores are module-level globals (decisions §2: the store *is* the document), and a reload
// used to start them empty — twenty cards gone for pressing F5. `sessionStorage` rather than
// `localStorage` because the document belongs to this tab's session: two tabs editing two
// pipelines must not overwrite each other, and closing the tab is the natural end of the work.
//
// Everything is guarded: there is no `sessionStorage` during SSR, a private window may throw on
// access, and whatever is in there may be from an older shape. In every one of those cases the
// answer is "start from `initial`", never "fail to load the app".

type Codec<T> = { encode: (value: T) => unknown; decode: (raw: unknown) => T };

const identity = <T,>(): Codec<T> => ({ encode: (v) => v, decode: (r) => r as T });

function read<T>(key: string, codec: Codec<T>): T | undefined {
  try {
    const raw = sessionStorage.getItem(key);
    return raw === null ? undefined : codec.decode(JSON.parse(raw));
  } catch {
    return undefined;
  }
}

function write(key: string, json: string) {
  try {
    sessionStorage.setItem(key, json);
  } catch {
    // Quota or a blocked store. The in-memory state is still right; only the backup failed.
  }
}

/**
 * A `createStore` that remembers itself.
 *
 * The write effect reads the whole store — `JSON.stringify` touches every leaf — so it tracks
 * every leaf and fires on any change. That one deep read is the cost of persistence, and it is
 * also the reason `json` is returned: anything else that needs the serialised document (the
 * probe) should read it from here rather than serialise again.
 */
export function persisted<T extends object>(
  key: string,
  initial: T,
  codec: Codec<T> = identity<T>(),
): [Store<T>, SetStoreFunction<T>, Accessor<string>] {
  const saved = read(key, codec);
  const [store, setStore] = createStore<T>(saved ?? initial);
  const json = createRoot(() => {
    const memo = createMemo(() => JSON.stringify(codec.encode(store)));
    createEffect(memo, (value) => write(key, value));
    return memo;
  });
  return [store, setStore, json];
}

export function persistedSignal<T>(key: string, initial: T): [Accessor<T>, Setter<T>] {
  const saved = read<T>(key, identity<T>());
  const [value, setValue] = createSignal<T>(saved === undefined ? initial : saved);
  createRoot(() => createEffect(value, (v) => write(key, JSON.stringify(v))));
  return [value, setValue];
}
```

(If `createRoot` is not exported by this Solid build under that name, use whatever `src/root.ts`-style file the app already uses to own module-level computations; check `grep -rn createRoot node_modules/solid-js/dist/solid.js | head -1`.)

- [ ] **Step 4: Wire the stores**

In `src/stores.ts`:

```ts
import { persisted, persistedSignal } from "./persist";
```

Replace the four `createStore` lines:

```ts
export const LOADER_STORE = persisted<LoaderStore>("dashi.loader", [] as LoaderStore).slice(0, 2) as
  ReturnType<typeof createStore<LoaderStore>>;
```

— no: keep the tuple shape callers destructure. Write it as:

```ts
const loader = persisted<LoaderStore>("dashi.loader", [] as LoaderStore);
export const LOADER_STORE: [Store<LoaderStore>, SetStoreFunction<LoaderStore>] = [loader[0], loader[1]];

/** `Interval` and `Set` are not JSON; carried as `{min,max}` and arrays, rebuilt on the way in. */
export const filtersCodec = {
  encode: (v: FiltersStore) => ({
    numerical: Object.fromEntries(Object.entries(v.numerical).map(([k, i]) => [k, i && { min: i.min, max: i.max }])),
    categorical: Object.fromEntries(Object.entries(v.categorical).map(([k, s]) => [k, s && [...s]])),
  }),
  decode: (raw: unknown): FiltersStore => {
    const r = raw as { numerical?: Record<string, { min: number; max: number } | null>; categorical?: Record<string, unknown[] | null> };
    return {
      numerical: Object.fromEntries(Object.entries(r.numerical ?? {}).map(([k, i]) => [k, i && new Interval(i.min, i.max)])),
      categorical: Object.fromEntries(Object.entries(r.categorical ?? {}).map(([k, l]) => [k, l && new Set(l)])),
    };
  },
};
const filters = persisted<FiltersStore>("dashi.filters", { numerical: {}, categorical: {} }, filtersCodec);
export const FILTERS_STORE: [Store<FiltersStore>, SetStoreFunction<FiltersStore>] = [filters[0], filters[1]];

// PROBE_STORE is *not* persisted: it is derived from the document and recomputes within 200 ms of
// load (Task 6). Persisting it would cost a write per probe for a value that is about to be replaced.
// `export const PROBE_STORE = createStore<ProbeStore>(emptyProbe());` stays exactly as it is.

const cards = persisted<CardsStore>("dashi.cards", emptyCards());
export const CARDS_STORE: [Store<CardsStore>, SetStoreFunction<CardsStore>] = [cards[0], cards[1]];
/** The document, serialised once. Persistence writes it; the probe (Task 6) keys on it. */
export const CARDS_JSON = cards[2];
```

Replace the confirmations signal:

```ts
const [confirmations, setConfirmations] = persistedSignal<Record<string, string>>("dashi.confirmations", {});
```

Import `Store` and `SetStoreFunction` types from `solid-js` at the top. The existing `const [cards, setCards] = CARDS_STORE;` further down conflicts with the new `cards` name — rename the new tuple `cardsPersisted`.

- [ ] **Step 5: Persist the last tab in `src/routes/index.tsx`**

```ts
import { persistedSignal } from "../persist";
const [lastTab, setLastTab] = persistedSignal<string>("dashi.tab", "load");
```

In `Home`, after `useSearchParams`:

```tsx
  // A bare `/` reopens where you were; a URL that names a tab wins. Read once, on mount.
  onSettled(() => {
    if (params.tab === undefined && lastTab() !== "load") setParams({ tab: lastTab() }, { replace: true });
  });
  createEffect(() => params.tab, (tab) => { if (tab !== undefined) setLastTab(tab); });
```

(`onSettled` and `createEffect` imported from `solid-js`.)

- [ ] **Step 6: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit && npm run lint && npm run build`
Expected: all pass. Tests that assumed empty stores now need `sessionStorage.clear()` in their `beforeEach` — `index.test.tsx` and `results.test.tsx` call `importCards(emptyCards())` already, which overwrites; add `sessionStorage.clear()` to both `beforeEach` blocks anyway so state cannot leak between files.

- [ ] **Step 7: Mutation-test**

In `persisted`, make `read` return `undefined` always. Expected: `persist.test.ts` "starts from what was saved" fails. Restore. Remove `createEffect(memo, …)`. Expected: "saves what changes" fails. Restore.

- [ ] **Step 8: Stop for review**

Report also: the visible effect — reload the page with cards defined and they are still there; `?tab=` absent → last tab reopens.

---

### Task 6: The probe — one serialise, debounced, sequence-guarded

**Files:**
- Modify: `src/left-tabs/processing.tsx:106–169` (`askProbe`, `runProbe`, the effect)
- Test: `src/left-tabs/processing.test.tsx`

**Interfaces:**
- Consumes: `CARDS_JSON` from `src/stores.ts` (Task 5).
- Produces: the continuous probe fires at most once per 200 ms of quiet; a reply is applied only if no later request was issued.

- [ ] **Step 1: Write the failing tests**

Append to `src/left-tabs/processing.test.tsx`:

```tsx
import { setNodeId } from '../stores';

describe('the continuous probe', () => {
  const probeCalls = () => postRequest.mock.calls.filter((c) => c[0] === 'probe-pipeline');

  it('coalesces a burst of edits into one request', async () => {
    // It fired one POST per committed edit. Every keystroke that commits — every field, every
    // chip — became a document-wide resolve on the server.
    vi.useFakeTimers();
    try {
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);   // settle the mount-time probe
      const n = probeCalls().length;
      setNodeId(0, 'a'); await flush();
      setNodeId(0, 'ab'); await flush();
      setNodeId(0, 'abc'); await flush();
      await vi.advanceTimersByTimeAsync(100);
      expect(probeCalls().length).toBe(n);        // still inside the quiet window
      await vi.advanceTimersByTimeAsync(200);
      expect(probeCalls().length).toBe(n + 1);    // one request for three edits
    } finally {
      vi.useRealTimers();
    }
  });

  it('discards a reply that arrives after a newer request was sent', async () => {
    // Replies are async and the server is not obliged to answer in order. Without a guard the
    // slow answer to the *old* document overwrote the fast answer to the new one.
    vi.useFakeTimers();
    const pending: Array<(v: unknown) => void> = [];
    postRequest.mockImplementation((page: string, body: { nodes?: { id: string }[] }) => {
      if (page === 'get-card-ir') return Promise.resolve(structuredClone(payload));
      if (page === 'probe-pipeline') {
        return new Promise((resolve) => pending.push((v) => resolve({ ...CLEAN_PROBE, cols: [body.nodes?.[0]?.id ?? ''] , ...(v as object) })));
      }
      return Promise.resolve([]);
    });
    try {
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      const { PROBE_STORE } = await import('../stores');
      setNodeId(0, 'first'); await flush(); await vi.advanceTimersByTimeAsync(250);
      setNodeId(0, 'second'); await flush(); await vi.advanceTimersByTimeAsync(250);
      expect(pending.length).toBeGreaterThanOrEqual(2);
      const [old, fresh] = pending.slice(-2);
      fresh({}); await flush(); await vi.advanceTimersByTimeAsync(0);
      old({});   await flush(); await vi.advanceTimersByTimeAsync(0);
      expect(PROBE_STORE[0].cols).toEqual(['second']);   // the old reply did not win
    } finally {
      vi.useRealTimers();
    }
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `npx vitest run src/left-tabs/processing.test.tsx -t "probe"`
Expected: FAIL — three requests instead of one; `cols` equals `['first']`.

- [ ] **Step 3: Implement**

In `processing.tsx`, replace `askProbe`, `runProbe` and the probe effect (lines 106–169) with:

```tsx
  /** Coerce a probe reply into something the store can hold, whatever the server sent. */
  const usableProbe = (result: unknown): ProbeStore => {
    const reported = result as ProbeStore | null;
    const ok = reported !== null && typeof reported === "object" &&
      Array.isArray(reported.nodes) && Array.isArray(reported.errors);
    return ok ? { ...reported, issues: Array.isArray(reported.issues) ? reported.issues : [] } : emptyProbe();
  };

  /** Ask once and get the shape back. Confirm uses this; the continuous probe below does too. */
  async function askProbe(document: CardsStore): Promise<ProbeStore> {
    return usableProbe(await postRequest("probe-pipeline", document, null));
  }

  // The continuous probe. Three things it does that a plain effect did not:
  //
  //   * reads the document from `CARDS_JSON`, which persistence already serialises — one deep
  //     read of the store instead of two;
  //   * waits 200 ms of quiet before asking, so a burst of edits is one request;
  //   * numbers each request and applies a reply only if it is still the newest, because
  //     replies are async and a slow answer to an old document used to overwrite a fast answer
  //     to the new one.
  let probeSeq = 0;
  let probeTimer: ReturnType<typeof setTimeout> | undefined;
  const PROBE_QUIET_MS = 200;

  createEffect(CARDS_JSON, (json) => {
    clearTimeout(probeTimer);
    probeTimer = setTimeout(() => {
      const document = JSON.parse(json) as CardsStore;
      if (document.nodes.length === 0) {
        probeSeq += 1;
        setProbe(reconcile(emptyProbe()));
        return;
      }
      const seq = ++probeSeq;
      void askProbe(document).then((answer) => {
        if (seq !== probeSeq) return;            // a newer request is out; this answer is stale
        setProbe(reconcile(answer));
      });
    }, PROBE_QUIET_MS);
  });
```

Add `CARDS_JSON` to the import from `../stores`. Remove the now-unused `runProbe`.

- [ ] **Step 4: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit && npm run lint`
Expected: all pass. Existing `index.test.tsx` probe tests use `waitFor`, which polls real time — they still pass because `waitFor` waits longer than 200 ms. If one times out, wrap that test's interaction in `vi.useFakeTimers()` + `advanceTimersByTimeAsync(250)` as above.

- [ ] **Step 5: Mutation-test**

Set `PROBE_QUIET_MS = 0`. Expected: "coalesces" fails (3 requests). Restore. Remove `if (seq !== probeSeq) return;`. Expected: "discards" fails. Restore.

- [ ] **Step 6: Stop for review**

---

### Task 7: Fetch the card descriptions once

**Files:**
- Modify: `DashiBoard/src/handlers.jl` (`get_card_ir`)
- Modify: `DashiBoard/test/dashiboard.jl` (after the existing `get-card-ir` block, ~line 214)
- Modify: `src/left-tabs/processing.tsx` (`loadIR`, the vocabulary effect)
- Modify: `src/fixtures/card-ir.regenerate.jl` — no change; the full payload is still what the fixture records.
- Test: `src/left-tabs/processing.test.tsx`

**Interfaces:**
- Produces: `POST /get-card-ir` accepts `include: ["defs"]` / `["cards"]` / both (default both); the response carries only the requested keys. Client fetches both once, then `defs` only.

- [ ] **Step 1: Julia test first**

In `DashiBoard/test/dashiboard.jl`, after the `# nulls are omitted rather than shipped` assertion block for `get-card-ir`:

```julia
        # `cards` is 96% of the payload and cannot change within a session — `card_ir` takes no
        # vocabulary. A client that has it once asks for `defs` alone afterwards.
        body = JSON.json((; cols = ["No", "TEMP"], nodes = String[], groups = String[], include = ["defs"]))
        resp = HTTP.post(url * "get-card-ir", body = body)
        only_defs = JSON.parse(resp.body)
        @test collect(keys(only_defs)) == ["defs"]
        @test only_defs["defs"]["col"]["enum"] == ["No", "TEMP"]
        @test length(resp.body) < 4000                     # against ~19 KB for the full payload
        body = JSON.json((; include = ["cards"]))
        resp = HTTP.post(url * "get-card-ir", body = body)
        @test collect(keys(JSON.parse(resp.body))) == ["cards"]
```

Run: `DASHIBOARD_CACHE=/tmp/dashi-test julia --project=DashiBoard/test DashiBoard/test/runtests.jl 2>&1 | grep -E "Test Failed|Error During" | head -3`
Expected: FAIL — keys are `["cards", "defs"]`.

- [ ] **Step 2: Implement the handler**

In `DashiBoard/src/handlers.jl`, `get_card_ir`:

```julia
function get_card_ir(req::HTTP.Request)
    spec = json_read(req)
    maybe_strings(key) = haskey(spec, key) ? collect(String, spec[key]) : nothing
    # Which halves to send. `cards` is the IR of every registered type and takes no vocabulary,
    # so it is the same answer for the life of the server; `defs` is the three enums and changes
    # with every column, group or node name. Measured: 18,449 of 19,152 bytes were `cards`, and
    # they were being refetched to update 242 bytes of enum.
    include = Set{String}(get(spec, "include", ["defs", "cards"]))
    parts = Pair{Symbol, Any}[]
    if "defs" in include
        variable_config = Pipelines.VariableConfig(
            nodes = maybe_strings("nodes"),
            groups = maybe_strings("groups"),
            cols = maybe_strings("cols"),
        )
        push!(parts, :defs => Pipelines.ir_definitions(variable_config))
    end
    if "cards" in include
        push!(parts, :cards => Dict{String, Any}(k => Pipelines.card_ir(k) for k in keys(Pipelines.CARD_SPECS)))
    end
    return json_response((; parts...); omit_null = true)
end
```

Run the Julia suite again. Expected: EXIT 0.

- [ ] **Step 3: UI test**

Append to `src/left-tabs/processing.test.tsx`:

```tsx
describe('the card IR', () => {
  it('is fetched whole once, then only its vocabulary', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(irCalls()).toBe(1));
    const first = postRequest.mock.calls.find((c) => c[0] === 'get-card-ir')![1] as { include?: string[] };
    expect(first.include ?? ['defs', 'cards']).toEqual(expect.arrayContaining(['cards']));

    addGroup();
    await waitFor(() => expect(irCalls()).toBe(2));
    const second = postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir')[1][1] as { include?: string[] };
    expect(second.include).toEqual(['defs']);
    // and the form still renders, from the cached cards
    await waitFor(() => expect(container.querySelector('#node-0-rescale-method-variant')).not.toBeNull());
  });
});
```

Adjust the mock in this file's `beforeEach` so `get-card-ir` honours `include`:

```tsx
      page === 'get-card-ir'
        ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                   const full = structuredClone(payload) as Record<string, unknown>;
                   return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
```

(with `body` as the second mock argument).

Run: `npx vitest run src/left-tabs/processing.test.tsx -t "card IR"`. Expected: FAIL — second call has no `include`.

- [ ] **Step 4: Implement the client**

In `processing.tsx`, `loadIR` becomes:

```tsx
  // `cards` is fetched once and kept; only `defs` follows the vocabulary. See the handler.
  const [cardIRs, setCardIRs] = createSignal<{ [type: string]: IRNode } | null>(null);

  async function loadIR() {
    const include = cardIRs() === null ? ["defs", "cards"] : ["defs"];
    const received = (await postRequest(
      "get-card-ir",
      {
        cols: metadata.map((entry) => entry.name),
        nodes: state.nodes.map((node) => node.id).filter((id): id is string => !!id),
        groups: Object.keys(state.groups),
        include,
      },
      null,
    )) as Partial<Payload> | null;
    if (!received || !received.defs) {
      setError("Could not reach DashiBoard. Is the server running?");
      return;
    }
    setError(null);
    if (received.cards) setCardIRs(received.cards);
    const cards = cardIRs();
    if (cards === null) return;                       // cannot happen on the first call
    setPayload({ defs: received.defs, cards });
    const types = Object.keys(cards).sort();
    if (!chosen() && types.length > 0) setChosen(types[0]);
  }
```

- [ ] **Step 5: Run the suite; measure**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit && npm run lint`
Expected: all pass.

Then, with the dev server and a `JULIA_DEBUG=DashiBoard` Julia server running, load a file and add a group; in the access log the second `get-card-ir` should be visibly faster and — using the browser's Network tab — ~2.6 KB rather than ~19 KB. Record both numbers in the report.

- [ ] **Step 6: Mutation-test**

Make `include` always `["defs", "cards"]` on the client. Expected: the UI test fails on `second.include`. Restore. In Julia, ignore `include`. Expected: the Julia test fails on `keys`. Restore.

- [ ] **Step 7: Stop for review**

---

### Task 8: A stable datasource in TableView

**Files:**
- Modify: `src/components/TableView.tsx:100–149`

**Interfaces:**
- Produces: the ag-grid datasource object is created once per `props.processed`; column changes update `columnDefs` without replacing the datasource.

- [ ] **Step 1: Restructure**

Replace `options` and the effect:

```tsx
  // Two effects, not one. The datasource is what the infinite row model pages through, and
  // handing the grid a *new* one resets its block cache and refetches from row 0 — so it is
  // built once per `processed` and never rebuilt for a column change. Columns are the cheap
  // half and update on their own.
  const datasource = createMemo(() => dataSource(props.processed));
  const columnDefs = createMemo(() =>
    props.metadata.map((x: Column) => ({
      field: x.name,
      headerName: x.name,
      valueFormatter: (params: { value: unknown }) => formatter(params.value, x.eltype),
    })),
  );

  createEffect(datasource, (next) => gridApi?.updateGridOptions({ datasource: next }));
  createEffect(columnDefs, (next) =>
    gridApi?.updateGridOptions({ columnDefs: next, suppressFieldDotNotation: true }),
  );
```

And change `dataSource` to take `processed: boolean` instead of `columnDefs`; the empty-columns branch moves to `columnDefs`: when `props.metadata.length === 0` the column effect passes `[]` and the grid shows no rows, so the empty datasource is no longer needed. Delete it.

- [ ] **Step 2: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit`
Expected: all pass (`loading.test.tsx` and `results.test.tsx` cover mount and paging).

- [ ] **Step 3: Measure — this is the verification**

This cannot be tested in jsdom (no layout, so the grid never pages). With both servers running: load `stress.csv`; count `fetch-data` lines in `/tmp/dashi.log`. Expected **1** (was 2). Then run a pipeline; count again for the results pane. Record in the report. If still 2, open the Network tab and record the two `offset` values — that decides whether the remaining fetch is paging or a reset.

- [ ] **Step 4: Stop for review**

---

### Task 9: Memoise the derived values

**Files:**
- Modify: `src/components/SelectorField.tsx:49–76`
- Modify: `src/left-tabs/processing.tsx:292–298, 397–413`
- Test: `src/components/SelectorField.test.tsx`

**Interfaces:**
- Produces: `rows`, `kinds`, `widget` in `SelectorField` are memos; `nodeState` is one memo per card.

- [ ] **Step 1: Write the failing test**

Append to `src/components/SelectorField.test.tsx`:

```tsx
import * as selector from '../selector';

  it('expands the document once per change, not once per read', () => {
    // `rows()` was a plain function called from every row's `casesFor`, the chip list, the writes
    // strip and the tab counts — O(values × items) expansions per render.
    const spy = vi.spyOn(selector, 'expand');
    render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs"
        value={[{ cols: ['TEMP', 'PRES'] }]} onChange={() => {}} />
    ));
    expect(spy.mock.calls.length).toBeLessThanOrEqual(2);   // mount, plus at most one settle
    spy.mockRestore();
  });
```

(Use whatever `itemNode`/`defs` the file's other tests already build.) Import `vi` from vitest if not already.

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/components/SelectorField.test.tsx -t "once per change"`
Expected: FAIL — `expand` called many more than 2 times.

- [ ] **Step 3: Implement**

In `SelectorField.tsx`:

```tsx
  const widget = createMemo(() => widgetFor(props.itemNode, props.defs));
  const kinds = createMemo(() => { /* body unchanged, reads widget() */ });
  const rows = createMemo(() => expand(asItems(props.value), kinds()));
```

(`createMemo` added to the import.) `optionsOf` and `chainOptions` stay functions of `widget()`, which is now memoised.

In `processing.tsx`, inside the `<For each={state.nodes}>` callback, before the JSX:

```tsx
          const nodeState = createMemo(() =>
            (unfinished()[index()]?.length ?? 0) > 0
              ? "incomplete"
              : confirmedNode(index())
                ? "confirmed"
                : "unconfirmed",
          );
```

and replace the seven `nodeState(index())` reads with `nodeState()`. Delete the outer `nodeState` function.

- [ ] **Step 4: Run the suite**

Run: `npx vitest run --reporter=dot && npx tsc --noEmit && npm run lint && npm run build`
Expected: all pass.

- [ ] **Step 5: Mutation-test**

Change `rows` back to a plain function. Expected: the new test fails. Restore.

- [ ] **Step 6: Stop for review**

---

## Not a task: the `dependency_graph` reply

No code. Text for the team leader, to send as-is:

> `group_names` was added in `b04ca7b` for A4 — `graphviz(::GroupDiGraph)` labels group vertices and needs the names in vertex order. The vertex order is fixed inside `dependency_graph` by `enumerate(pairs(group_configs))`; the minimal alternative is `collect(String, keys(group_configs))` at the call site in `dag.jl:20`, which iterates the same `Dict` and so gives the same order. Returning it was a choice to keep the order in one place rather than rely on two iterations agreeing. It is one line either way; happy to revert if you prefer the four-value signature.

---

## Self-review

**Spec coverage.** A1 → Task 1. A3 → Task 2. Tab in URL → Task 3. Split → Task 4. sessionStorage (all stores, confirmations, tab) → Task 5. A2 → Task 6. A4 → Task 7. A7 → Task 8. A5, A6 → Task 9. `dependency_graph` → the reply. A8, A9, A10 → out of scope, as the spec says.

**Placeholders.** None: every step has its code or its exact command.

**Type consistency.** `persisted` returns a 3-tuple `[store, setter, json]`; `stores.ts` re-exports 2-tuples for the four `*_STORE` names and `CARDS_JSON` as the third element of the cards tuple; Task 6 reads `CARDS_JSON`. `IRField`'s `idPrefix` is used by Task 1's test via the `??` fallback so Task 1 passes before Task 2 lands. `renderHome` is defined in Task 3 and used by Task 4.
