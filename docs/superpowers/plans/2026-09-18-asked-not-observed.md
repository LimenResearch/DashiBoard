# Asked, not observed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Red comes from verdicts only — the "Needs attention" line reads them, Confirm refuses a document that cannot build, a failed run stops writing the probe store, and an upload asks on the author's behalf instead of being refused.

**Architecture:** `stores.ts` already holds verdicts bound to content signatures and a function that turns a server's pointed issues into rejected verdicts on a snapshot; this plan makes that function the only bridge from issues to red (rename, drop its probe-store write), adds a `documentFindings` reading of a probe reply (errors that point at no item), and a `checkNames` UI rule for duplicate card names. `processing.tsx`, `GroupsEditor.tsx` and `results.tsx` then consume those three: Confirm prepends `documentFindings`, the line iterates `verdictOf`, and the upload handler probes the imported snapshot once.

**Tech Stack:** SolidJS 2 (rc.6) + TypeScript in `dashiboard-ui/`; vitest + `@solidjs/testing-library` (jsdom); pnpm. No Julia.

**Spec:** `docs/superpowers/specs/2026-09-18-asked-not-observed-design.md`

## Global Constraints

- UI only: every change is under `dashiboard-ui/`. The team leader is working in `Pipelines/` in parallel; do not touch `Pipelines/` or `DashiBoard/`.
- Work in a worktree on a side branch `sdd/asked-not-observed` from `ds-DashiUI` @ `dfb77cb`; one commit per task on the side branch; nothing lands on `ds-DashiUI` — the owner reviews and merges (owner's standing decision, 2026-09-16).
- TDD: every test is written first and watched failing; a test that passes before its production change is mutation-checked (change the production code so it must fail, watch it fail, restore).
- Before hand-over of every task, from `dashiboard-ui/`: `npx vitest run` (all green, `0` lines containing `STRICT_READ_UNTRACKED`), `npx tsc --noEmit`, `pnpm run lint` (no *new* warnings — 20 exist at baseline), `pnpm run build`.
- Every comment written explains *why* — the reason the code is shaped as it is — in the register of the surrounding code.
- Redirect every test run to a file and read the whole file; never grep-filter a run you are diagnosing.
- Messages, verbatim (the spec's copy): `There is already a card called "<name>".`, `There is already a card without a name.`, `The uploaded document does not build:`, `Could not reach DashiBoard to check this document — is the server running?`.

---

## File structure

| file | responsibility after this plan |
|---|---|
| `src/stores.ts` | verdicts; `rejectFromIssues(issues, document)` (renamed from `reportRunIssues`, no probe write); `documentFindings(answer)`; `itemKey` |
| `src/completeness.ts` | what the UI answers alone: `checkNode` (existing) and `checkNames(nodes)` (new) |
| `src/left-tabs/processing.tsx` | Confirm (cards) uses `documentFindings`; the upload handler asks; the upload text under the buttons |
| `src/components/GroupsEditor.tsx` | Confirm (groups) uses `documentFindings` |
| `src/left-tabs/results.tsx` | the line reads `verdictOf`; no probe read, no document-fault block; run failure calls `rejectFromIssues` |
| tests | `stores.test.ts`, `completeness.test.ts`, `processing.test.tsx`, `GroupsEditor.test.tsx`, `results.test.tsx` |

Task order: 1 → 2 → 3 → 4. Task 3 needs Task 1's rename; Task 4 needs Tasks 1 and 2.

---

### Task 1: The store's two rules — `rejectFromIssues` stops writing the probe store; `checkNames` finds duplicate card names

**Files:**
- Modify: `dashiboard-ui/src/stores.ts:246-281` (`reportRunIssues` → `rejectFromIssues`), and add `documentFindings` after `itemKey` (`:283-288`)
- Modify: `dashiboard-ui/src/completeness.ts:66-71` (add `checkNames` after `checkNode`; amend the header comment)
- Modify (rename call sites only): `dashiboard-ui/src/left-tabs/results.tsx:10,32,107`, `dashiboard-ui/src/left-tabs/processing.test.tsx:6,40,314,324`, `dashiboard-ui/src/components/GroupsEditor.tsx:195`, `dashiboard-ui/src/components/GroupsEditor.test.tsx:7,328,344,359,410`, `dashiboard-ui/src/stores.test.ts:475,501`
- Test: `dashiboard-ui/src/stores.test.ts`, `dashiboard-ui/src/completeness.test.ts`

**Interfaces:**
- Consumes: `recordVerdict(key, value, verdict, findings)`, `itemKey(pointer)`, `issueFindings(issues)`, `PROBE_STORE`, `Incompleteness`, `PipelineNode`, `ProbeStore` — all existing.
- Produces:
  - `export function rejectFromIssues(issues: ProbeIssue[], document: Pick<CardsStore, "nodes" | "groups"> = exportCards()): void` — records a `rejected` verdict on every item an error issue points at; touches nothing else.
  - `export function documentFindings(answer: Pick<ProbeStore, "valid" | "issues" | "errors">): Incompleteness[]` — the findings that belong to the *document*: the message of every error issue whose pointer names no item, plus `answer.errors` when `valid === false` and no error issue names any item. Empty when the document builds or every error is somebody's.
  - `export function checkNames(nodes: readonly PipelineNode[]): { index: number; finding: Incompleteness }[]` — one entry per node whose id (a missing id counts as `""`) an earlier node already has.

- [ ] **Step 1: Write the failing store tests**

Append to the `describe` block in `dashiboard-ui/src/stores.test.ts` that holds the two `reportRunIssues` tests (`:475`, `:501`), after renaming both of those calls to `s.rejectFromIssues` (they keep their assertions):

```ts
  it('rejectFromIssues records the rejection and leaves the probe store alone', async () => {
    // The probe store has one writer, the continuous probe, sequenced by `probeSeq`
    // (`processing.tsx`). A second, unsequenced writer let an older probe reply erase a failed
    // run's issues — measured 2026-09-17 — and the line next to Run lost the run's names.
    const s = await import('./stores');
    s.importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} });
    s.PROBE_STORE[1](reconcile(s.emptyProbe()));
    s.rejectFromIssues([{
      pointer: '/nodes/0/card/inputs', reason: 'required', severity: 'error', found: null,
      allowed: null, missing: ['inputs'], related: ['/nodes/0/card/inputs'], message: 'x',
    }]);
    await flush();
    expect(s.verdictOf('node:0', s.exportCards().nodes[0])?.verdict).toBe('rejected');
    expect(s.PROBE_STORE[0].valid).toBe(true);
    expect(s.PROBE_STORE[0].issues).toEqual([]);
  });

  describe('documentFindings', () => {
    const pointed = {
      pointer: '/nodes/0/card/method', reason: 'type', severity: 'error' as const, found: 'zscore',
      allowed: null, missing: [], related: [], message: 'Schema Validation Error',
    };
    it('is the errors when the document does not build and no issue names an item', async () => {
      // The server's literal reply for two cards named `a` (measured 2026-09-17).
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: false, issues: [], errors: ['ArgumentError: Encountered nodes with equal `id`'],
      })).toEqual([{ message: 'ArgumentError: Encountered nodes with equal `id`' }]);
    });
    it('is empty when every error is pointed at an item', async () => {
      // A schema failure's `errors` is the issues' own messages run together; those are read on
      // the items, and confirming an unrelated card must still go green.
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: false, issues: [pointed], errors: ['1 schema validation error:\nSchema Validation Error'],
      })).toEqual([]);
    });
    it('is empty when the document builds', async () => {
      const s = await import('./stores');
      expect(s.documentFindings({ valid: true, issues: [], errors: [] })).toEqual([]);
    });
    it('carries the message of an issue that points at no item, beside pointed ones', async () => {
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: false,
        issues: [pointed, { ...pointed, pointer: '', message: 'nothing to run' }],
        errors: ['x'],
      })).toEqual([{ message: 'nothing to run' }]);
    });
    it('ignores warnings', async () => {
      const s = await import('./stores');
      expect(s.documentFindings({
        valid: true, issues: [{ ...pointed, pointer: '', severity: 'warning' }], errors: [],
      })).toEqual([]);
    });
  });
```

`reconcile` and `flush` are already imported in this file; check the top of the file and add them if not (`import { flush, reconcile } from 'solid-js'`).

- [ ] **Step 2: Write the failing completeness tests**

Append to `dashiboard-ui/src/completeness.test.ts`:

```ts
import { checkNames } from './completeness';

describe('checkNames', () => {
  // Two cards with one name is a document the server cannot build, and it says so with no
  // pointer (`Encountered nodes with equal \`id\``, measured 2026-09-17) — so no card could carry
  // it. The UI owns the rule since `setNodeId` refuses a taken name; an uploaded document is the
  // one way two cards still arrive with one name, and this places the finding on the later one.
  const card = { type: 'rescale' };
  it('marks every card after the first with a taken name, not the first', () => {
    expect(checkNames([{ id: 'a', card }, { id: 'b', card }, { id: 'a', card }, { id: 'a', card }]))
      .toEqual([
        { index: 2, finding: { message: 'There is already a card called "a".' } },
        { index: 3, finding: { message: 'There is already a card called "a".' } },
      ]);
  });
  it('counts a missing id as "", which only one card can be', () => {
    // `Pipelines.get_id` defaults a missing id to "", so two unnamed cards collide the same way.
    expect(checkNames([{ card }, { id: '', card }])).toEqual([
      { index: 1, finding: { message: 'There is already a card without a name.' } },
    ]);
  });
  it('finds nothing when names are distinct', () => {
    expect(checkNames([{ id: 'a', card }, { card }, { id: 'b', card }])).toEqual([]);
  });
});
```

Merge the import with the existing `import { checkNode } from './completeness'` line.

- [ ] **Step 3: Run both files, watch them fail**

Run from `dashiboard-ui/`:
```bash
npx vitest run src/stores.test.ts src/completeness.test.ts > /tmp/t1-red.log 2>&1; cat /tmp/t1-red.log
```
Expected: the two renamed tests and the new ones fail with `s.rejectFromIssues is not a function`, `s.documentFindings is not a function`, `checkNames` not exported. Nothing else fails.

- [ ] **Step 4: Rename and rewrite in `stores.ts`**

Replace `reportRunIssues` (`stores.ts:246-281`, docstring included) with:

```ts
/**
 * A server's pointed issues, as rejected verdicts on the items they point at.
 *
 * The one bridge from issues to red. A failed run and an upload both come through here, so an
 * issue is placed the same way whoever asked; Confirm places its own through `issueFindings`
 * with the same shape. Warnings are not findings and are skipped. An issue whose pointer names
 * no item is not this function's to place — `documentFindings` reads those.
 *
 * `document` is what the server was *sent*, not the store as it is when the reply lands: the
 * author may have edited in between, and a verdict on content the server never saw is the one
 * thing a verdict must never be. Defaults to the current document for callers with no request
 * in flight.
 *
 * Writes verdicts and nothing else. It used to write `PROBE_STORE` too, outside the continuous
 * probe's `probeSeq` guard, so an older probe reply landing afterwards erased a failed run's
 * issues from the store (measured 2026-09-17). The store has one writer now.
 */
export function rejectFromIssues(
  issues: ProbeIssue[],
  document: Pick<CardsStore, "nodes" | "groups"> = exportCards(),
) {
  const byItem = new Map<string, ProbeIssue[]>();
  for (const issue of issues) {
    if (issue.severity === "warning") continue;
    const key = itemKey(issue.pointer);
    if (key === null) continue;
    byItem.set(key, [...(byItem.get(key) ?? []), issue]);
  }
  for (const [key, own] of byItem) {
    const value = itemValue(key, document);
    if (value === undefined) continue;
    recordVerdict(key, value, "rejected", issueFindings(own));
  }
}
```

After `itemKey` (`stores.ts:283-288`) add:

```ts
/**
 * What a probe reply says about the *document* rather than about any item.
 *
 * The server reports in layers: schema failures and empty groups come back pointed at an item,
 * before building; build faults — a loop, two cards with one id, a `through` chain nothing can
 * resolve — come back as `errors` with `issues: []`. So `errors` belong to the document exactly
 * when the document does not build and no error issue names an item. Otherwise they are the
 * items' own messages run together (a schema failure's `errors` is that concatenation), already
 * read on the items, and confirming an unrelated card must still go green. An issue whose
 * pointer names no item counts as the document's too; none is emitted today.
 */
export function documentFindings(
  answer: Pick<ProbeStore, "valid" | "issues" | "errors">,
): Incompleteness[] {
  const errors = answer.issues.filter((issue) => issue.severity !== "warning");
  const loose = errors.filter((issue) => itemKey(issue.pointer) === null);
  const anyPointed = errors.length > loose.length;
  const findings: Incompleteness[] = loose.map((issue) => ({ message: issue.message }));
  if (answer.valid === false && !anyPointed) {
    findings.push(...answer.errors.map((message) => ({ message })));
  }
  return findings;
}
```

Then rename every call site listed under **Files** from `reportRunIssues` to `rejectFromIssues` — imports, calls and the four comments that name it (`results.tsx:32`, `processing.test.tsx:40`, `GroupsEditor.tsx:195`, `GroupsEditor.test.tsx:328`). `git grep -n reportRunIssues dashiboard-ui/src` must return nothing afterwards.

- [ ] **Step 5: Add `checkNames` to `completeness.ts`**

After `checkNode` (`completeness.ts:66-71`):

```ts
/**
 * Cards that share a name with an earlier card — the later ones, each with its finding.
 *
 * The server refuses the document (`Encountered nodes with equal \`id\``) with no pointer, so it
 * cannot say which card; the UI can. This is the rule `setNodeId` enforces at the name field,
 * so the only way two cards still arrive with one name is an uploaded document, and an upload
 * places the finding here rather than refusing the file (owner, 2026-09-18: the form exists to
 * fix documents). A missing id counts as "" — `Pipelines.get_id`'s default — so two unnamed
 * cards collide the same way. The first holder keeps its name unmarked: it is the later card
 * that has to change.
 */
export function checkNames(
  nodes: readonly PipelineNode[],
): { index: number; finding: Incompleteness }[] {
  const seen = new Set<string>();
  const out: { index: number; finding: Incompleteness }[] = [];
  nodes.forEach((node, index) => {
    const id = node.id ?? "";
    if (seen.has(id)) {
      out.push({
        index,
        finding: {
          message: id === ""
            ? "There is already a card without a name."
            : `There is already a card called "${id}".`,
        },
      });
    }
    seen.add(id);
  });
  return out;
}
```

In the header comment of `completeness.ts` (`:12-13`), the sentence "while an unproduced reference, a duplicate id or a cycle is the server's" is now half wrong: change it to "while an unproduced reference or a cycle is the server's — and a duplicate id, once the server's, is ours since `setNodeId` refuses one (`checkNames`)".

- [ ] **Step 6: Run both files, watch them pass**

```bash
npx vitest run src/stores.test.ts src/completeness.test.ts > /tmp/t1-green.log 2>&1; cat /tmp/t1-green.log
```
Expected: all pass.

- [ ] **Step 7: Mutation-check the probe-store assertion**

Temporarily put the old write back at the top of `rejectFromIssues`:
```ts
  const [, setProbe] = PROBE_STORE;
  setProbe((draft) => { draft.valid = false; draft.issues = issues; });
```
Run `npx vitest run src/stores.test.ts -t "leaves the probe store alone" > /tmp/t1-mut.log 2>&1; cat /tmp/t1-mut.log` — expected: that one test FAILS on `valid` being `false`. Remove the two lines again and re-run: PASS.

- [ ] **Step 8: Whole suite, types, lint, build**

```bash
npx vitest run > /tmp/t1-full.log 2>&1; tail -8 /tmp/t1-full.log; grep -c STRICT_READ_UNTRACKED /tmp/t1-full.log
npx tsc --noEmit
pnpm run lint
pnpm run build
```
Expected: all tests pass (the renamed callers compile — `results.tsx` still calls the function on the run path); `0` STRICT lines; tsc clean; lint with no new warning; build ok. If `results.tsx` or a test still imports `reportRunIssues`, tsc will say so.

- [ ] **Step 9: Commit**

```bash
git add dashiboard-ui/src/stores.ts dashiboard-ui/src/stores.test.ts dashiboard-ui/src/completeness.ts dashiboard-ui/src/completeness.test.ts dashiboard-ui/src/left-tabs/results.tsx dashiboard-ui/src/left-tabs/processing.test.tsx dashiboard-ui/src/components/GroupsEditor.tsx dashiboard-ui/src/components/GroupsEditor.test.tsx
git commit -m "stores: one bridge from issues to red; the probe store has one writer; checkNames"
```

---

### Task 2: Confirm refuses a document that cannot build — cards and groups

**Files:**
- Modify: `dashiboard-ui/src/left-tabs/processing.tsx:217-233` (`graphFindings`), `:12-34` (import `documentFindings`)
- Modify: `dashiboard-ui/src/components/GroupsEditor.tsx:148-186` (the Confirm handler), its `../stores` import
- Test: `dashiboard-ui/src/left-tabs/processing.test.tsx`, `dashiboard-ui/src/components/GroupsEditor.test.tsx`

**Interfaces:**
- Consumes: `documentFindings(answer)` from Task 1; existing `graphFindings`, `issueFindings`, `issuesForGroup`, `recordVerdict`, `askProbe`.
- Produces: no new exports. Behaviour: a card's or a group's Confirm records `rejected` with `documentFindings(answer)` first, then its own findings, whenever `documentFindings` is non-empty.

- [ ] **Step 1: Write the failing card tests**

Append to `dashiboard-ui/src/left-tabs/processing.test.tsx` (the file's `beforeEach` seeds one `rescale` card `r` and group `g`, mocks `get-card-ir`, `probe-pipeline` → `CLEAN_PROBE`, `validate-card` → valid):

```ts
describe('Confirm on a document that cannot build', () => {
  // Measured 2026-09-17 with the server's own replies: two cards named `a`, or a loop, come
  // back `valid:false` with the sentence in `errors` and `issues: []` — no item to point at —
  // and Confirm went green. The fault is the document's, so whichever item is asked carries it.
  const cardConfirm = (c: HTMLElement) =>
    c.querySelector('button[title="mark this card deliberately finished"]')!;
  const cardDot = (c: HTMLElement) =>
    [...c.querySelectorAll('details')].find((d) => d.querySelector('[data-card-title]'))!
      .querySelector('[data-state]')!;
  const serveProbe = (reply: unknown) =>
    postRequest.mockImplementation((page: string, body: unknown) =>
      Promise.resolve(
        page === 'get-card-ir'
          ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                     const full = structuredClone(payload) as Record<string, unknown>;
                     return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
        : page === 'probe-pipeline' ? reply
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );

  it('rejects the card with the server\'s sentence for two cards of one name', async () => {
    serveProbe({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['ArgumentError: Encountered nodes with equal `id`'] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('rejected'));
    expect(container.querySelector('[data-finding]')!.textContent).toContain('Encountered nodes with equal `id`');
  });

  it('rejects the card for a loop the same way', async () => {
    serveProbe({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['The input graph contains at least one loop.'] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('rejected'));
    expect(container.querySelector('[data-finding]')!.textContent).toContain('at least one loop');
  });

  it('confirms green when the only fault is another card\'s, pointed at that card', async () => {
    // A schema failure's `errors` repeats the pointed issue's message; that is card 2's
    // business, and card 1 is fine.
    importCards({
      nodes: [
        { id: 'r', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } },
        { id: 's', card: { type: 'rescale' } },
      ],
      groups: {},
    });
    serveProbe({ valid: false, kind: 'pipeline', cols: [],
      errors: ['1 schema validation error:\nSchema Validation Error for card in node 2'],
      issues: [{ pointer: '/nodes/1/card', reason: 'required', severity: 'error', found: null,
        allowed: null, missing: ['method'], related: ['/nodes/1/card/method'], message: 'Schema Validation Error for card in node 2' }] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelectorAll('button[title="mark this card deliberately finished"]').length).toBe(2));
    fireEvent.click(container.querySelectorAll('button[title="mark this card deliberately finished"]')[0]);
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
    expect(container.querySelector('[data-state="rejected"]')).toBeNull();
  });
});
```

- [ ] **Step 2: Write the failing group tests**

Append to `dashiboard-ui/src/components/GroupsEditor.test.tsx` (the file's `mount()` renders the editor; `beforeEach` resets verdicts and the probe store):

```ts
describe('Confirm on a document that cannot build', () => {
  // The same rule as a card's Confirm: a fault with no item pointer is the document's, and the
  // group that was asked carries it.
  it('rejects the group with the server\'s sentence', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], issues: [],
            errors: ['ArgumentError: Encountered nodes with equal `id`'] }
        : []));
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.querySelector('[data-state="rejected"]')).not.toBeNull());
    expect(container.querySelector('[data-finding]')!.textContent).toContain('equal `id`');
  });

  it('confirms green when the only fault is pointed at a card', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [],
            errors: ['1 schema validation error:\nSchema Validation Error for card in node 1'],
            issues: [{ pointer: '/nodes/0/card', reason: 'required', severity: 'error', found: null,
              allowed: null, missing: ['method'], related: ['/nodes/0/card/method'], message: 'Schema Validation Error for card in node 1' }] }
        : []));
    addGroup('weather');
    setGroup('weather', [{ cols: 'TEMP' }]);
    const { container, getByText } = mount();
    await flush();
    fireEvent.click(getByText('Confirm'));
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
  });
});
```

Check that `[data-finding]` is the attribute the group's finding `<p>` carries (`GroupsEditor.tsx:198-206`); it is.

- [ ] **Step 3: Run both files, watch the new tests fail**

```bash
npx vitest run src/left-tabs/processing.test.tsx src/components/GroupsEditor.test.tsx > /tmp/t2-red.log 2>&1; cat /tmp/t2-red.log
```
Expected: the four "rejects" tests fail (the dot reads `confirmed`, no `[data-finding]`); the two "confirms green" tests PASS already — note that: they are guards, mutation-checked in Step 6.

- [ ] **Step 4: Cards — `graphFindings` gains the document rule**

In `processing.tsx`, add `documentFindings` to the `../stores` import, and change `graphFindings` (`:221-233`) to:

```ts
  /**
   * What only the whole document can answer: a reference nothing produces, a schema failure
   * `validate-card` could not see because it needs the other cards — and, first, whether the
   * document builds at all. A fault with no item pointer (a loop, two cards with one id) is
   * the document's, and the card that was asked carries it: measured 2026-09-17, Confirm read
   * only the issues pointed at this card and went green on a document the server refused.
   */
  const graphFindings = (answer: ProbeStore, index: number): Incompleteness[] => {
    // A warning never counts as unfinished — it still renders live through the probe path, in
    // the warning style, but does not stop Confirm from marking the card done.
    const schema = issueFindings(
      issuesForNode(answer.issues, index).filter(
        (issue) => issue.reason !== "unproduced" && issue.severity !== "warning",
      ),
    );
    const absent = answer.nodes[index]?.unproduced ?? [];
    return [
      ...documentFindings(answer),
      ...schema,
      ...(absent.length > 0
        ? [{ message: `Nothing produces ${absent.join(", ")} — check the pass-through chain.` }]
        : []),
    ];
  };
```

- [ ] **Step 5: Groups — the Confirm handler gains the same rule**

In `GroupsEditor.tsx`, add `documentFindings` to the `../stores` import, and change the `decide(...)` call at the end of the Confirm handler (`:179-181`) to:

```tsx
                            // A warning is not a finding: it renders live, amber, and never
                            // stops Confirm. The document's own faults come first — a loop or a
                            // duplicate id has no item to point at, so the group that was asked
                            // carries them (same rule as `graphFindings` in processing.tsx).
                            decide([
                              ...documentFindings(answer),
                              ...issueFindings(
                                issuesForGroup(answer.issues, name).filter((issue) => issue.severity !== "warning"),
                              ),
                            ]);
```

- [ ] **Step 6: Run, watch them pass; mutation-check the two guards**

```bash
npx vitest run src/left-tabs/processing.test.tsx src/components/GroupsEditor.test.tsx > /tmp/t2-green.log 2>&1; cat /tmp/t2-green.log
```
Expected: all pass. Then mutate `documentFindings` in `stores.ts` so it returns `answer.errors` whenever `valid === false` (delete `&& !anyPointed`), run the same two files: the two "confirms green" tests must FAIL. Restore and re-run: PASS.

- [ ] **Step 7: Whole suite, types, lint, build**

```bash
npx vitest run > /tmp/full.log 2>&1; tail -8 /tmp/full.log; grep -c STRICT_READ_UNTRACKED /tmp/full.log
npx tsc --noEmit
pnpm run lint
pnpm run build
```
Expected: all tests pass; `0` STRICT lines; tsc clean; lint with no new warning (20 at baseline); build ok.

- [ ] **Step 8: Commit**

```bash
git add dashiboard-ui/src/left-tabs/processing.tsx dashiboard-ui/src/left-tabs/processing.test.tsx dashiboard-ui/src/components/GroupsEditor.tsx dashiboard-ui/src/components/GroupsEditor.test.tsx
git commit -m "Confirm refuses a document that cannot build: the item asked carries the server's sentence"
```

---

### Task 3: The line reads verdicts; the document-fault block goes

**Files:**
- Modify: `dashiboard-ui/src/left-tabs/results.tsx:9-12` (imports), `:191-243` (`probe`, `attention`, `needsAttention`, `documentFaults`), `:263-275` (the block)
- Test: `dashiboard-ui/src/left-tabs/results.test.tsx:293-375` (the `describe('the pointer next to Run pipeline')` block — rewritten)

**Interfaces:**
- Consumes: `verdictOf(key, value)`, `CARDS_STORE`, `rejectFromIssues` (Task 1), `recordVerdict`, `forgetVerdict`, `setCardField`, `PROBE_STORE` (tests only).
- Produces: no exports. `[data-needs-attention]` lists rejected items; `[data-document-faults]` no longer exists.

- [ ] **Step 1: Rewrite the line's tests**

In `results.test.tsx`, replace the whole `describe('the pointer next to Run pipeline', …)` block (`:293-375`) with:

```ts
describe('the pointer next to Run pipeline', () => {
  // Decided 2026-09-18: the line reads the verdicts and nothing else — the same source as the
  // dots — so it names an item only once a Confirm, a failed run or an upload rejected it. It
  // used to read the continuous probe and went red before anyone asked, which is exactly what
  // the cards and groups stopped doing on 2026-09-17.
  const issue = (pointer: string, severity: 'error' | 'warning' = 'error') => ({
    pointer, reason: 'required', severity, found: null, allowed: null, missing: [], related: [], message: 'x',
  });
  const line = (c: HTMLElement) => c.querySelector('[data-needs-attention]');

  it('is absent while the probe objects and nobody asked', async () => {
    PROBE_STORE[1]((d) => { d.valid = false; d.issues = [issue('/nodes/0/card')]; d.errors = ['x']; });
    await flush();
    const { container } = render(() => <Results />);
    expect(line(container)).toBeNull();
  });

  it('names what was rejected — a card by id, an unnamed card by position, a group by name', async () => {
    importCards({
      nodes: [{ id: 'cluster', card: { type: 'cluster' } }, { card: { type: 'split' } }],
      groups: { group_2: [] },
    });
    const doc = exportCards();
    recordVerdict('node:0', doc.nodes[0], 'rejected', [{ message: 'x' }]);
    recordVerdict('node:1', doc.nodes[1], 'rejected', [{ message: 'x' }]);
    recordVerdict('group:group_2', doc.groups.group_2, 'rejected', [{ message: 'x' }]);
    await flush();
    const { container } = render(() => <Results />);
    expect(line(container)!.textContent).toMatch(/Needs attention: cluster, card 2, group_2/);
    expect(line(container)!.className).toMatch(/destructive/);
  });

  it('drops an item once it is edited, and when its verdict is forgotten', async () => {
    const doc = exportCards();
    recordVerdict('node:0', doc.nodes[0], 'rejected', [{ message: 'x' }]);
    recordVerdict('node:1', doc.nodes[1], 'rejected', [{ message: 'x' }]);
    await flush();
    const { container } = render(() => <Results />);
    expect(line(container)!.textContent).toMatch(/rescaled, grouped/);
    setCardField(0, 'suffix', 'edited');            // the verdict no longer matches the content
    await flush();
    expect(line(container)!.textContent).toMatch(/Needs attention: grouped$/);
    forgetVerdict('node:1');
    await flush();
    expect(line(container)).toBeNull();
  });

  it('keeps a failed run\'s names when a stale probe reply lands afterwards', async () => {
    // Measured 2026-09-17: the run wrote its issues into the probe store, an older probe reply
    // overwrote them, and the line went blank while the card stayed red. One source now.
    serve({ valid: false, kind: 'pipeline', errors: ['x'], issues: [issue('/nodes/0/card')] });
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(line(container)).not.toBeNull());
    PROBE_STORE[1](reconcile(emptyProbe()));      // the older question answers clean, last
    await flush();
    expect(line(container)!.textContent).toMatch(/rescaled/);
  });

  it('names nothing for a failed run with no item to point at; the text is under Run', async () => {
    serve({ valid: false, kind: 'pipeline', errors: ['The input graph contains at least one loop.'], issues: [] });
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(line(container)).toBeNull();
    expect(container.querySelector('[data-run-error]')!.textContent).toContain('at least one loop');
    expect(container.querySelector('[data-document-faults]')).toBeNull();
  });
});
```

Add `recordVerdict, forgetVerdict, setCardField` to the file's `../stores` import (`:13-15`); `reconcile`, `emptyProbe`, `PROBE_STORE`, `importCards`, `exportCards`, `serve`, `runPipeline` are already there. The seeded `DOCUMENT` has nodes `rescaled` and `grouped`, which the third test relies on.

- [ ] **Step 2: Run, watch them fail**

```bash
npx vitest run src/left-tabs/results.test.tsx -t "the pointer next to Run pipeline" > /tmp/t3-red.log 2>&1; cat /tmp/t3-red.log
```
Expected: "is absent while the probe objects" fails (the line is present); "names what was rejected" fails (nothing is on the line); "drops an item" fails; "keeps a failed run's names" — check the log: it may pass or fail depending on timing; "names nothing … the text is under Run" fails on `[data-document-faults]` being present. Record which passed before the change; they are mutation-checked in Step 5.

- [ ] **Step 3: Rewrite the line in `results.tsx`**

Replace `:191-243` (from `const [probe] = PROBE_STORE;` through `documentFaults`) with:

```tsx
  /**
   * Who was asked and found wanting, by name — the one top-level signal, visible from every tab
   * and with the cards folded.
   *
   * Read from the verdicts, the same source as the dots, so the two cannot disagree: an item is
   * named once a Confirm, a failed run or an upload rejected its current content, and an edit
   * expires the verdict and drops it (decided 2026-09-18). This line used to read the continuous
   * probe and named items before anyone asked — the very "red before asked" the items gave up
   * on 2026-09-17. Names only: the findings are read on the items. Nodes by id, or "card N" for
   * an unnamed one, in document order; then groups by name. Running is still allowed: the line
   * says where to look, it does not gate.
   */
  const needsAttention = createMemo(() => {
    const names: string[] = [];
    cards.nodes.forEach((node, at) => {
      if (verdictOf(`node:${at}`, node)?.verdict === "rejected") names.push(node.id || `card ${at + 1}`);
    });
    for (const [name, items] of Object.entries(cards.groups)) {
      if (verdictOf(`group:${name}`, items)?.verdict === "rejected") names.push(name);
    }
    return names;
  });
```

Delete the `[data-document-faults]` block (`:263-275`, the comment included). Change the `../stores` import to
`CARDS_STORE, exportCards, itemKey, rejectFromIssues, verdictOf, type ProbeIssue, type VariableSummary` — `PROBE_STORE` is no longer read here. `For` stays imported (the failure block uses it).

`verdictOf` reads a store proxy here (`cards.nodes[at]`), as `processing.tsx`'s per-card memo does; the signature is `JSON.stringify` of the value, which serialises a Solid store proxy as its plain content.

- [ ] **Step 4: Run, watch them pass**

```bash
npx vitest run src/left-tabs/results.test.tsx > /tmp/t3-green.log 2>&1; cat /tmp/t3-green.log
```
Expected: the whole file passes, including the older run tests that use `[data-run-error]`.

- [ ] **Step 5: Mutation-check whichever tests passed in Step 2**

For "keeps a failed run's names": comment out the `recordVerdict` call inside `rejectFromIssues` (`stores.ts`), run the file — that test must FAIL (nothing on the line after the run). Restore, re-run: PASS. For any other test that passed in Step 2, find the one production line it depends on, break it, watch it fail, restore.

- [ ] **Step 6: Whole suite, types, lint, build**

```bash
npx vitest run > /tmp/full.log 2>&1; tail -8 /tmp/full.log; grep -c STRICT_READ_UNTRACKED /tmp/full.log
npx tsc --noEmit
pnpm run lint
pnpm run build
```
Expected: all tests pass; `0` STRICT lines; tsc clean; lint with no new warning (20 at baseline); build ok. `tsc` will report `PROBE_STORE` unused if the import was not trimmed.

- [ ] **Step 7: Commit**

```bash
git add dashiboard-ui/src/left-tabs/results.tsx dashiboard-ui/src/left-tabs/results.test.tsx
git commit -m "results: the line names what was rejected, from the verdicts; the document-fault block goes"
```

---

### Task 4: An upload asks

**Files:**
- Modify: `dashiboard-ui/src/left-tabs/processing.tsx:1-40` (imports), the component body (add the upload handler and its signal next to the probe wiring, `:150-190`), `:540-552` (the buttons; the text under them)
- Test: `dashiboard-ui/src/left-tabs/processing.test.tsx`

**Interfaces:**
- Consumes: `importCards`, `exportCards`, `rejectFromIssues` (Task 1), `checkNames` (Task 1), `documentFindings` (Task 1), `recordVerdict`, `askProbe`, `CARDS_JSON`, `UploadJSONButton` (`components/JSON.tsx:16-28`: `onChange(value)` after `loadJSON(fileInput, def)`), the mocked `loadJSON` in the test file's `vi.mock('../requests')`.
- Produces: `[data-upload-error]` block under the Download/Upload row, present only after an upload the server could not build or reach; cleared by the next upload or the next document edit.

- [ ] **Step 1: Write the failing tests**

Append to `processing.test.tsx`. The upload goes through the real `UploadJSONButton`: the file input's `change` calls the mocked `loadJSON`, so the test makes that mock resolve to the document.

```ts
import { loadJSON } from '../requests';   // the mock from vi.mock above; add to the imports at the top

describe('an upload asks', () => {
  // Decided 2026-09-18: a broken document is never refused — the form exists to fix it — and
  // uploading is an act of asking: what the server rejects is red on the items, what the UI can
  // place itself (a taken name) is red on the later card, and what nobody can place is said
  // under the Upload button. Nothing is confirmed green: nobody looked at it.
  const upload = async (container: HTMLElement, doc: unknown) => {
    vi.mocked(loadJSON).mockResolvedValue(doc);
    fireEvent.change(container.querySelector('input[type="file"]')!);
    await flush();
    await new Promise((r) => setTimeout(r, 0));    // the handler's probe resolves on a microtask
    await flush();
  };
  const dots = (c: HTMLElement) =>
    [...c.querySelectorAll('details')]
      .filter((d) => d.querySelector('[data-card-title]'))
      .map((d) => d.querySelector('[data-state]')!.getAttribute('data-state'));
  const withProbe = (reply: unknown) =>
    postRequest.mockImplementation((page: string, body: unknown) =>
      Promise.resolve(
        page === 'get-card-ir'
          ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                     const full = structuredClone(payload) as Record<string, unknown>;
                     return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
        : page === 'probe-pipeline' ? reply
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );
  const two = {
    nodes: [
      { id: 'a', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } },
      { id: 'b', card: { type: 'rescale' } },
    ],
    groups: {},
  };

  it('rejects the items the server points at, and leaves the rest amber', async () => {
    withProbe({ valid: false, kind: 'pipeline', cols: [],
      errors: ['1 schema validation error:\nSchema Validation Error for card in node 2'],
      issues: [{ pointer: '/nodes/1/card', reason: 'required', severity: 'error', found: null,
        allowed: null, missing: ['method'], related: ['/nodes/1/card/method'], message: 'Schema Validation Error for card in node 2' }] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('input[type="file"]')).not.toBeNull());
    await upload(container, two);
    await waitFor(() => expect(dots(container)).toEqual(['unconfirmed', 'rejected']));
    expect(container.querySelector('[data-upload-error]')).toBeNull();
    expect(container.querySelector('[data-state="confirmed"]')).toBeNull();
  });

  it('marks the later of two cards with one name, with the UI\'s own sentence', async () => {
    withProbe({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['ArgumentError: Encountered nodes with equal `id`'] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('input[type="file"]')).not.toBeNull());
    await upload(container, { ...two, nodes: [two.nodes[0], { ...two.nodes[1], id: 'a' }] });
    await waitFor(() => expect(dots(container)).toEqual(['unconfirmed', 'rejected']));
    expect(container.querySelector('[data-finding]')!.textContent).toContain('There is already a card called "a".');
    // The server's duplicate-id sentence is placed, so it is not repeated under the button.
    expect(container.querySelector('[data-upload-error]')).toBeNull();
  });

  it('says under the button what nobody can place, and an edit clears it', async () => {
    withProbe({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['The input graph contains at least one loop.'] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('input[type="file"]')).not.toBeNull());
    await upload(container, two);
    await waitFor(() => expect(container.querySelector('[data-upload-error]')).not.toBeNull());
    expect(container.querySelector('[data-upload-error]')!.textContent).toContain('The uploaded document does not build:');
    expect(container.querySelector('[data-upload-error]')!.textContent).toContain('at least one loop');
    expect(dots(container)).toEqual(['unconfirmed', 'unconfirmed']);
    setCardField(0, 'suffix', 'edited');
    await flush();
    expect(container.querySelector('[data-upload-error]')).toBeNull();
  });

  it('says so when the server cannot be reached', async () => {
    withProbe(null);
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('input[type="file"]')).not.toBeNull());
    await upload(container, two);
    await waitFor(() => expect(container.querySelector('[data-upload-error]')).not.toBeNull());
    expect(container.querySelector('[data-upload-error]')!.textContent).toMatch(/could not reach/i);
  });
});
```

`vi.mocked` needs `vi` imported (it is). If `loadJSON` in the `vi.mock` factory is `vi.fn()` (it is, `processing.test.tsx:11-15`), `vi.mocked(loadJSON).mockResolvedValue` works on the imported binding.

- [ ] **Step 2: Run, watch them fail**

```bash
npx vitest run src/left-tabs/processing.test.tsx -t "an upload asks" > /tmp/t4-red.log 2>&1; cat /tmp/t4-red.log
```
Expected: all four fail — dots stay `unconfirmed`, no `[data-upload-error]`, no finding.

- [ ] **Step 3: The handler and the text**

In `processing.tsx`: add `checkNames` to the `../completeness` import, `rejectFromIssues, documentFindings` to the `../stores` import. Next to the probe wiring (after the `onCleanup` at `:184-187`) add:

```tsx
  /**
   * An upload is an act of asking.
   *
   * The document is loaded exactly as it came — a broken one included, because fixing it here
   * is what the form is for (owner, 2026-09-18) — and then asked about once, on the author's
   * behalf, from the imported snapshot. What the server points at is rejected on its item, the
   * way a failed run's issues are; a taken name is ours to place (`checkNames`), since the
   * server reports it with no pointer; whatever is left has no item and is said here, under the
   * button that asked, until the next upload or the next edit. Nothing is confirmed: an item the
   * probe has nothing against stays amber, because nobody looked at it.
   *
   * Its own `askProbe`, not the continuous probe's reply: that one writes the store and nothing
   * else, and by the time it answers the document may already be a later one.
   */
  const [uploadReport, setUploadReport] = createSignal<string[] | null>(null);
  // The uploaded document, serialised as `persisted` serialises the store (`JSON.stringify` of
  // the plain object; the identity codec), so "the document changed since the upload" is one
  // string comparison against `CARDS_JSON`. Cleared with the report.
  let uploadedJson: string | null = null;
  createEffect(CARDS_JSON, (json) => {
    if (uploadedJson !== null && json !== uploadedJson) {
      uploadedJson = null;
      setUploadReport(null);
    }
  });
  async function uploadCards(value: CardsStore) {
    // One plain copy is what is stored, what is asked about and what the verdicts bind to —
    // not `exportCards()` read back right after `importCards`, which on Solid 2 may still be the
    // previous document in this tick.
    const document = structuredClone(value);
    importCards(document);
    uploadedJson = JSON.stringify(document);
    setUploadReport(null);
    const taken = checkNames(document.nodes);
    for (const { index, finding } of taken) {
      recordVerdict(`node:${index}`, document.nodes[index], "rejected", [finding]);
    }
    const answer = await askProbe(document);
    if (answer === null) {
      setUploadReport(["Could not reach DashiBoard to check this document — is the server running?"]);
      return;
    }
    rejectFromIssues(answer.issues, document);
    // With a taken name placed above, the server's one build error for this document is that
    // same duplicate id (construction stops there — measured), already on the later card; what
    // else there is surfaces once the names are fixed. Otherwise the loose sentences are said.
    if (taken.length > 0) return;
    const loose = documentFindings(answer).map((finding) => finding.message);
    if (loose.length > 0) setUploadReport(loose);
  }
```

Change the button (`:545-550`) to `onChange={(value: CardsStore) => void uploadCards(value)}`, and after the `<div class="flex gap-2">…</div>` that holds the two buttons add:

```tsx
      {/* The server's sentence about an uploaded document nobody could place on an item — a
          loop, an unreachable server. Same dress as a failed run's text under Run, because it is
          the same kind of thing. Gone on the next upload or the next edit. */}
      <Show when={uploadReport()} keyed>
        {(lines: string[]) => (
          <div
            data-upload-error
            class="mx-3 my-2 rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-control-xs text-destructive"
          >
            <p class="mb-1.5 font-semibold">The uploaded document does not build:</p>
            <For each={lines}>
              {(line: string) => <p class="font-mono break-words whitespace-pre-wrap">{line}</p>}
            </For>
          </div>
        )}
      </Show>
```

`createSignal`, `createEffect`, `untrack`, `Show`, `For` are already imported in this file.

The `CARDS_JSON` effect: `importCards` changes the JSON and the effect runs for that change too, with `json` equal to `JSON.stringify(document)` — `persisted` builds its string with `JSON.stringify(codec.encode(store))` and the cards store uses the identity codec, and `reconcile(structuredClone(document))` keeps key order — so the report survives the upload's own write and goes on the next edit. If the third test's "an edit clears it" step shows the report gone *before* the edit, the two strings differ: print both in the test once, find the difference, fix the serialisation of `uploadedJson` — do not weaken the test.

- [ ] **Step 4: Run, watch them pass**

```bash
npx vitest run src/left-tabs/processing.test.tsx > /tmp/t4-green.log 2>&1; cat /tmp/t4-green.log
```
Expected: the file passes. If the third test's "an edit clears it" step fails because the effect cleared the report on the upload itself, read the note in Step 3.

- [ ] **Step 5: Mutation-check** — remove the `checkNames` loop: the second test must FAIL; restore. Remove the `rejectFromIssues` call: the first must FAIL; restore.

- [ ] **Step 6: Whole suite, types, lint, build**

```bash
npx vitest run > /tmp/full.log 2>&1; tail -8 /tmp/full.log; grep -c STRICT_READ_UNTRACKED /tmp/full.log
npx tsc --noEmit
pnpm run lint
pnpm run build
```
Expected: all tests pass; `0` STRICT lines; tsc clean; lint with no new warning (20 at baseline); build ok.

- [ ] **Step 7: Commit**

```bash
git add dashiboard-ui/src/left-tabs/processing.tsx dashiboard-ui/src/left-tabs/processing.test.tsx
git commit -m "upload asks: what the server rejects is red on the items, a taken name on the later card, the rest under the button"
```

---

## Hand-over

After Task 4: the whole suite, `tsc`, lint (no new warnings) and build from the final tree; `git grep -n "reportRunIssues\|data-document-faults" dashiboard-ui/src` returns nothing; the todo file `.superpowers/sdd/todos/2026-09-17-needs-attention-from-verdicts.md` gets item 1 and 3b moved to CLOSED with the four commits. The owner's browser checks are in the spec, §8.
