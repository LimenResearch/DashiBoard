# SelectorField Keyboard Entry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `SelectorField` with two ways in — the panel of switches, and a typed entry (`cols:` `bill_length` `@impute` Enter) that walks the same steps — on every field that takes a selector, offering only what an item may refer to, and dropping references to things that are not there.

**Architecture:** The grammar is a pure state machine (`selectorEntry.ts`) with no DOM; `SelectorField` is rearranged around it (header chips, text box with tokens, a panel that folds and that the box drives) and keeps `selector.ts` untouched, so a typed entry emits exactly the row a click emits. The server adds `referable` to the probe reply (who each item may refer to without a loop); the UI narrows vocabularies with it. A store function prunes references to missing columns, nodes and groups and reports them to an amber notice.

**Tech Stack:** SolidJS 2 (rc.6) + TypeScript, vitest + `@solidjs/testing-library` (jsdom), pnpm, in `dashiboard-ui/`; Julia 1.12 (HTTP.jl, JSON.jl, Graphs.jl) in `DashiBoard/`.

**Spec:** `docs/superpowers/specs/2026-09-21-selector-field-keyboard-entry-design.md`

## Global Constraints

- Only `dashiboard-ui/` and `DashiBoard/` change. `Pipelines/` and `DataIngestion/` are not touched.
- Worktree on a side branch `sdd/selector-entry` from `ds-DashiUI`; one commit per task; the owner reviews and merges.
- TDD: every test written first and watched failing; a test that passes before its production change is mutation-checked.
- `selector.ts` does not change. The existing document-contract tests in `SelectorField.test.tsx` (case C, case E, chain order, no empty item) keep their assertions; only how they *drive* the control may change.
- Comments say what a passage is for, in one to three lines: no measurements, dates, audit identifiers or history.
- A Solid 2 signal is not written during a component's setup; a store setter takes a function; two user actions in a test are two ticks (`await flush()` between them).
- UI verification before every UI commit, from `dashiboard-ui/`: `npx vitest run` (all green, `0` lines containing `STRICT_READ_UNTRACKED`, no `stderr` blocks), `npx tsc --noEmit`, `pnpm run lint` (16 warnings at baseline, none new), `pnpm run build`.
- Julia verification before the Julia commit, from the repository root: `DASHIBOARD_CACHE=$(mktemp -d) julia --project=DashiBoard/test --startup-file=no DashiBoard/test/dashiboard.jl > /tmp/dashi.log 2>&1; echo "exit $?"` for the cycle, and `DashiBoard/test/runtests.jl` once at the end. Redirect to a file and read it whole.
- Copy, verbatim: chip and pill notation `kind:value@node@node`; buttons `direct`, `through…`; help button `aria-label="how to type a selection"`; placeholder `nodes: name @node, then Enter`; removed-references notice starts `References removed — not in the table or the document:`.
- Hooks the tests use: `[data-selector]` root, `[data-chip="cols:PRES@sp"]`, `[data-chip-remove]`, `[data-move="earlier"|"later"]`, `[data-entry]` the input, `[data-token]`, `[data-suggestion="<value>"]`, `[data-pick="direct"|"through"]`, `[data-panel]`, `[data-fold]`, `[data-help]`, `[data-dropped-references]`.

---

## File structure

| file | responsibility |
|---|---|
| `src/selectorEntry.ts` (new) | the typed grammar: state, `suggestions`, `step`, `matches` |
| `src/components/SelectorField.tsx` | header chips, text box, fold, panel; reads `selectorEntry` and `selector` |
| `src/components/SelectorHelp.tsx` (new) | the `?` button and its key list |
| `src/components/IRField.tsx`, `src/components/GroupsEditor.tsx` | call sites: no outer `Collapsible`; pass `required` and the fold |
| `src/ir.ts` | `onlyOptions(defs, key, allowed)` beside `withoutOption` |
| `src/stores.ts`, `src/probe.ts` | `ProbeStore.referable`; `pruneReferences`, `droppedReferences` |
| `src/left-tabs/processing.tsx`, `src/left-tabs/loading.tsx` | narrow by `referable`; prune on load; the notice |
| `DashiBoard/src/handlers.jl`, `DashiBoard/test/dashiboard.jl` | `referable` in the probe reply |

Task order: 1 (grammar) → 2 (server) → 3 (layout) → 4 (text box) → 5 (chips by keyboard, help) → 6 (referable in the UI) → 7 (pruning). 2 is independent of 1 and 3–5.

---

### Task 1: The grammar, as data

**Files:**
- Create: `dashiboard-ui/src/selectorEntry.ts`, `dashiboard-ui/src/selectorEntry.test.ts`

**Interfaces — Produces:**

```ts
import type { SelectorRow } from "./selector";

/** What can be typed: the kinds on offer, each kind's names, and the nodes a chain may use. */
export type EntryVocabulary = { kinds: string[]; options: Record<string, string[]>; chain: string[] };
export type EntryState = {
  kind: string | null; name: string | null; chain: string[];
  text: string;        // the fragment being typed; "@zsc" while typing a chain step
  open: boolean;       // whether the suggestion list is showing
  highlight: number;   // index into `suggestions(...)`
};
export type EntryInput =
  | { type: "text"; value: string } | { type: "tab" } | { type: "enter" } | { type: "backspace" }
  | { type: "escape" } | { type: "down" } | { type: "up" }
  | { type: "pick"; value: string; how: "continue" | "direct" | "through" };
export type EntryStep = { state: EntryState; emit?: SelectorRow; leave?: true };

export const emptyEntry: EntryState;
export function matches(query: string, options: readonly string[]): string[];
export function stageOf(state: EntryState): "kind" | "name" | "chain" | "done";
export function suggestions(state: EntryState, vocabulary: EntryVocabulary): string[];
export function step(state: EntryState, input: EntryInput, vocabulary: EntryVocabulary, single?: boolean): EntryStep;
```

- [ ] **Step 1: Write the failing tests** — `selectorEntry.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { emptyEntry, matches, stageOf, suggestions, step, type EntryState, type EntryInput, type EntryVocabulary } from './selectorEntry';

const V: EntryVocabulary = {
  kinds: ['nodes', 'groups', 'cols'],
  options: { nodes: ['zscore', 'impute'], groups: ['bills'], cols: ['bill_length', 'flipper_length', 'with space', 'a@b'] },
  chain: ['zscore', 'impute'],
};
/** Feed inputs in order; return the last state and every row emitted on the way. */
const walk = (inputs: EntryInput[], vocabulary = V, single = false, from: EntryState = emptyEntry) => {
  let state = from; const emitted = []; let left = false;
  for (const input of inputs) {
    const next = step(state, input, vocabulary, single);
    state = next.state; if (next.emit) emitted.push(next.emit); if (next.leave) left = true;
  }
  return { state, emitted, left };
};
const text = (value: string): EntryInput => ({ type: 'text', value });
const TAB: EntryInput = { type: 'tab' }; const ENTER: EntryInput = { type: 'enter' };
const BACK: EntryInput = { type: 'backspace' }; const ESC: EntryInput = { type: 'escape' };

describe('matches', () => {
  it('lists names that start with the text first, then names that contain it, each in the given order', () => {
    expect(matches('len', ['flipper_length', 'length', 'bill_length'])).toEqual(['length', 'flipper_length', 'bill_length']);
    expect(matches('', ['b', 'a'])).toEqual(['b', 'a']);
    expect(matches('BILL', ['bill_length'])).toEqual(['bill_length']);
    expect(matches('zzz', ['bill_length'])).toEqual([]);
  });
});

describe('the typed entry', () => {
  it('opens nothing by itself, and TAB on an idle box leaves the field', () => {
    expect(emptyEntry.open).toBe(false);
    expect(walk([TAB]).left).toBe(true);
  });

  it('offers the kinds on the first keystroke, and on Down', () => {
    expect(suggestions(walk([text('c')]).state, V)).toEqual(['cols']);
    expect(suggestions(walk([{ type: 'down' }]).state, V)).toEqual(['nodes', 'groups', 'cols']);
  });

  it('walks kind, name, chain, finish', () => {
    const { state, emitted } = walk([text('c'), TAB, text('bill'), TAB, text('@imp'), TAB, text('@zsc'), TAB, ENTER]);
    expect(emitted).toEqual([{ kind: 'cols', value: 'bill_length', chain: ['impute', 'zscore'] }]);
    // the kind stays for the next entry; the list is closed, so the next TAB leaves
    expect(state).toEqual({ kind: 'cols', name: null, chain: [], text: '', open: false, highlight: 0 });
    expect(step(state, TAB, V).leave).toBe(true);
  });

  it('shows every name of the kind once the kind is accepted', () => {
    expect(suggestions(walk([text('g'), TAB]).state, V)).toEqual(['bills']);
    expect(stageOf(walk([text('g'), TAB]).state)).toBe('name');
  });

  it('accepts a kind typed out with its colon', () => {
    expect(walk([text('cols:')]).state.kind).toBe('cols');
  });

  it('ENTER accepts the highlighted match and finishes; a name with no chain is direct', () => {
    expect(walk([text('c'), TAB, text('flip'), ENTER]).emitted).toEqual([{ kind: 'cols', value: 'flipper_length', chain: [] }]);
    expect(walk([text('c'), TAB, text('bill'), TAB, text('@imp'), ENTER]).emitted)
      .toEqual([{ kind: 'cols', value: 'bill_length', chain: ['impute'] }]);
  });

  it('Up and Down choose another match before TAB', () => {
    const { emitted } = walk([text('c'), TAB, text('length'), { type: 'down' }, TAB, ENTER]);
    expect(emitted[0].value).toBe('flipper_length');
  });

  it('`@` typed after a name fragment accepts the top match and starts the chain', () => {
    const { state } = walk([text('c'), TAB, text('bill@')]);
    expect(state.name).toBe('bill_length');
    expect(stageOf(state)).toBe('chain');
    expect(suggestions(state, V)).toEqual(['zscore', 'impute']);
  });

  it('takes names with a space or an `@` in them whole, since nothing is parsed', () => {
    expect(walk([text('c'), TAB, text('with'), TAB, ENTER]).emitted[0].value).toBe('with space');
    expect(walk([text('c'), TAB, text('a@b'), TAB, ENTER]).emitted[0].value).toBe('a@b');
  });

  it('does nothing on ENTER with only a kind, or with a fragment that matches nothing', () => {
    expect(walk([text('c'), TAB, ENTER]).emitted).toEqual([]);
    expect(walk([text('c'), TAB, text('zzz'), ENTER]).emitted).toEqual([]);
    expect(walk([text('c'), TAB, text('zzz'), TAB]).state.name).toBeNull();
  });

  it('offers no chain when there are no nodes to pass through', () => {
    const none = { ...V, chain: [] };
    expect(suggestions(walk([text('c'), TAB, text('bill'), TAB, text('@')], none).state, none)).toEqual([]);
  });

  it('Backspace with nothing typed removes the last token whole, the kind last', () => {
    const full = walk([text('c'), TAB, text('bill'), TAB, text('@imp'), TAB]).state;
    const a = step(full, BACK, V).state;       expect(a.chain).toEqual([]);
    const b = step(a, BACK, V).state;          expect(b.name).toBeNull();
    const c = step(b, BACK, V).state;          expect(c.kind).toBeNull();
  });

  it('Esc closes the list, then clears the entry', () => {
    const typing = walk([text('c'), TAB, text('bill')]).state;
    const closed = step(typing, ESC, V).state;
    expect(closed.open).toBe(false);
    expect(closed.kind).toBe('cols');
    expect(step(closed, ESC, V).state).toEqual(emptyEntry);
  });

  it('a pick from the list is TAB, ENTER, or "through" by mouse', () => {
    const named = walk([text('c'), TAB]).state;
    expect(step(named, { type: 'pick', value: 'bill_length', how: 'direct' }, V).emit)
      .toEqual({ kind: 'cols', value: 'bill_length', chain: [] });
    const through = step(named, { type: 'pick', value: 'bill_length', how: 'through' }, V).state;
    expect(through.name).toBe('bill_length');
    expect(through.text).toBe('@');
    expect(suggestions(through, V)).toEqual(['zscore', 'impute']);
    expect(step(emptyEntry, { type: 'pick', value: 'groups', how: 'continue' }, V).state.kind).toBe('groups');
  });

  it('in single mode ENTER clears the kind too', () => {
    expect(walk([text('c'), TAB, text('bill'), ENTER], V, true).state).toEqual(emptyEntry);
  });
});
```

- [ ] **Step 2: Run, watch it fail** — `npx vitest run src/selectorEntry.test.ts > /tmp/t1-red.log 2>&1; cat /tmp/t1-red.log`. Expected: cannot resolve `./selectorEntry`.

- [ ] **Step 3: Write `selectorEntry.ts`**

```ts
import type { SelectorRow } from "./selector";

// The typed way into a selector: kind → name → optional chain → finish, the steps the panel of
// switches takes by mouse. Pure data, so the whole grammar is tested without a DOM, and what it
// emits is the row a click in the panel emits.

export type EntryVocabulary = { kinds: string[]; options: Record<string, string[]>; chain: string[] };
export type EntryState = {
  kind: string | null; name: string | null; chain: string[];
  text: string; open: boolean; highlight: number;
};
export type EntryInput =
  | { type: "text"; value: string } | { type: "tab" } | { type: "enter" } | { type: "backspace" }
  | { type: "escape" } | { type: "down" } | { type: "up" }
  | { type: "pick"; value: string; how: "continue" | "direct" | "through" };
export type EntryStep = { state: EntryState; emit?: SelectorRow; leave?: true };

export const emptyEntry: EntryState = { kind: null, name: null, chain: [], text: "", open: false, highlight: 0 };

/** Names starting with the text, then names containing it; each in the order given. */
export function matches(query: string, options: readonly string[]): string[] {
  const q = query.toLowerCase();
  if (q === "") return [...options];
  const starts = options.filter((o) => o.toLowerCase().startsWith(q));
  const contains = options.filter((o) => !o.toLowerCase().startsWith(q) && o.toLowerCase().includes(q));
  return [...starts, ...contains];
}

/** Which part of an entry the text is for. After a name, only a chain step (`@…`) can follow. */
export function stageOf(state: EntryState): "kind" | "name" | "chain" | "done" {
  if (state.kind === null) return "kind";
  if (state.name === null) return "name";
  return state.text.startsWith("@") ? "chain" : "done";
}

export function suggestions(state: EntryState, vocabulary: EntryVocabulary): string[] {
  switch (stageOf(state)) {
    case "kind": return matches(state.text, vocabulary.kinds);
    case "name": return matches(state.text, vocabulary.options[state.kind!] ?? []);
    case "chain": return matches(state.text.slice(1), vocabulary.chain);
    default: return [];
  }
}

/** The state after `value` is accepted for the current stage. */
function accept(state: EntryState, value: string): EntryState {
  switch (stageOf(state)) {
    case "kind": return { ...state, kind: value, text: "", open: true, highlight: 0 };
    case "name": return { ...state, name: value, text: "", open: false, highlight: 0 };
    case "chain": return { ...state, chain: [...state.chain, value], text: "", open: false, highlight: 0 };
    default: return state;
  }
}

const highlighted = (state: EntryState, vocabulary: EntryVocabulary): string | undefined =>
  state.open ? suggestions(state, vocabulary)[state.highlight] : undefined;

function finish(state: EntryState, single: boolean): EntryStep {
  if (state.kind === null || state.name === null) return { state };
  const emit: SelectorRow = { kind: state.kind, value: state.name, chain: state.chain };
  return { emit, state: single ? emptyEntry : { ...emptyEntry, kind: state.kind } };
}

export function step(state: EntryState, input: EntryInput, vocabulary: EntryVocabulary, single = false): EntryStep {
  switch (input.type) {
    case "text": {
      const value = input.value;
      // `cols:` typed out, and `bill@` typed through, both accept what came before the mark.
      if (stageOf(state) === "kind" && value.endsWith(":")) {
        const top = matches(value.slice(0, -1), vocabulary.kinds)[0];
        return { state: top === undefined ? { ...state, text: value, open: true, highlight: 0 } : accept({ ...state, text: value.slice(0, -1) }, top) };
      }
      if (stageOf(state) === "name" && value.endsWith("@") && !(vocabulary.options[state.kind!] ?? []).some((o) => o.toLowerCase().startsWith(value.toLowerCase()))) {
        const top = matches(value.slice(0, -1), vocabulary.options[state.kind!] ?? [])[0];
        if (top !== undefined) return { state: { ...accept({ ...state, text: value.slice(0, -1) }, top), text: "@", open: true } };
      }
      return { state: { ...state, text: value, open: true, highlight: 0 } };
    }
    case "down":
    case "up": {
      if (!state.open) return { state: { ...state, open: true, highlight: 0 } };
      const count = suggestions(state, vocabulary).length;
      if (count === 0) return { state };
      const delta = input.type === "down" ? 1 : -1;
      return { state: { ...state, highlight: (state.highlight + delta + count) % count } };
    }
    case "tab": {
      if (!state.open) return { state, leave: true };
      const value = highlighted(state, vocabulary);
      return { state: value === undefined ? state : accept(state, value) };
    }
    case "enter": {
      // ENTER takes the highlighted match only for something typed: with nothing typed it
      // finishes what is already accepted, and never picks the first name off an open list.
      const stage = stageOf(state);
      const query = stage === "chain" ? state.text.slice(1) : state.text;
      if (stage === "kind" || query === "") return finish({ ...state, text: "" }, single);
      const value = highlighted(state, vocabulary);
      return value === undefined ? { state } : finish(accept(state, value), single);
    }
    case "backspace": {
      if (state.text !== "") return { state };
      if (state.chain.length > 0) return { state: { ...state, chain: state.chain.slice(0, -1), open: false } };
      if (state.name !== null) return { state: { ...state, name: null, open: false } };
      return { state: { ...emptyEntry } };
    }
    case "escape":
      return { state: state.open ? { ...state, open: false } : emptyEntry };
    case "pick": {
      const accepted = accept({ ...state, open: true }, input.value);
      if (input.how === "direct") return finish(accepted, single);
      if (input.how === "through") return { state: { ...accepted, text: "@", open: true, highlight: 0 } };
      return { state: accepted };
    }
  }
}
```

- [ ] **Step 4: Run, watch it pass** — same command, `/tmp/t1-green.log`. If the `a@b` case fails, the `@` rule in `text` is accepting too eagerly: it must only fire when no name on offer still *starts with* what was typed — fix the rule, not the test.

- [ ] **Step 5: Full UI verification; commit**

```bash
git add dashiboard-ui/src/selectorEntry.ts dashiboard-ui/src/selectorEntry.test.ts
git commit -m "selector entry: the typed grammar as a pure state machine"
```

---

### Task 2: The server says what each item may refer to

**Files:**
- Modify: `DashiBoard/src/DashiBoard.jl` (the `using Graphs:` line), `DashiBoard/src/handlers.jl` (after `loop_issues`; `probe_pipeline`)
- Test: `DashiBoard/test/dashiboard.jl` (inside `@testset "request"`, after `@testset "loops"`)

**Interfaces — Produces:** every `probe-pipeline` reply carries `referable`: `null` when the dependency graph cannot be built, else

```json
{"nodes": [{"nodes": ["a"], "groups": ["g"]}, …one per card, by index…],
 "groups": {"g": {"nodes": ["a"], "groups": []}}}
```

Each entry lists the nodes and groups that item may name: everything except itself and what depends on it.

- [ ] **Step 1: Write the failing tests** — append inside `@testset "request"`:

```julia
        # What a card or a group may refer to without making a loop: everything but itself and
        # what depends on it. Sent with the probe so a picker offers only that.
        @testset "referable" begin
            rescale(id, input) = (; id, card = Dict(
                "type" => "rescale", "method" => Dict("type" => "zscore"),
                "inputs" => [input], "suffix" => id,
            ))
            probe(nodes, groups) = JSON.parse(HTTP.post(url * "probe-pipeline",
                body = JSON.json((; filters = [], nodes, groups))).body)

            # a ← b ← c, and a group g that reads b
            chain = probe(
                [rescale("a", Dict("cols" => "TEMP")), rescale("b", Dict("nodes" => "a")), rescale("c", Dict("nodes" => "b"))],
                Dict("g" => [Dict("nodes" => "b")]),
            )
            r = chain["referable"]
            @test r["nodes"][1] == Dict("nodes" => [], "groups" => [])             # everything depends on a
            @test r["nodes"][2] == Dict("nodes" => ["a"], "groups" => [])
            @test r["nodes"][3] == Dict("nodes" => ["a", "b"], "groups" => ["g"])
            @test r["groups"]["g"] == Dict("nodes" => ["a", "b", "c"], "groups" => [])

            # still answered for a document that does not build: a loop
            looped = probe([rescale("a", Dict("nodes" => "b")), rescale("b", Dict("nodes" => "a"))], Dict{String, Any}())
            @test looped["valid"] == false
            @test looped["referable"]["nodes"] == [Dict("nodes" => [], "groups" => []), Dict("nodes" => [], "groups" => [])]

            # and absent when the graph itself cannot be built
            twins = probe([rescale("a", Dict("cols" => "TEMP")), rescale("a", Dict("cols" => "TEMP"))], Dict{String, Any}())
            @test twins["referable"] === nothing
        end
```

`g` reads `b`, so `g` depends on `b` and on `a`; `c` does not depend on `g`, so `g` may name `c`.

- [ ] **Step 2: Run, watch it fail** — expected: `KeyError: "referable"`.

- [ ] **Step 3: Implement**

`DashiBoard.jl`: `using Graphs: strongly_connected_components, has_edge, gdistances, nv`.

`handlers.jl`, after `loop_issues`:

```julia
"""
    referable(nodes, groups)

For every card (by index) and group (by name), the nodes and groups it may refer to without
making a loop: all of them except itself and what depends on it. `nothing` when the dependency
graph cannot be built. Edges run from a dependency to what depends on it, so what depends on an
item is what can be reached from it.
"""
function referable(nodes::AbstractVector, groups::AbstractDict)
    graph, = try
        Pipelines.dependency_graph(nodes, groups)
    catch
        return nothing
    end
    n_nodes = length(nodes)
    ids = Pipelines.get_id.(nodes)
    group_names = collect(String, keys(groups))
    function allowed(vertex)
        free = findall(==(typemax(Int)), gdistances(graph, vertex))
        return (;
            nodes = String[ids[i] for i in free if i <= n_nodes],
            groups = String[group_names[i - n_nodes] for i in free if i > n_nodes],
        )
    end
    return (;
        nodes = [allowed(i) for i in 1:n_nodes],
        groups = Dict(name => allowed(n_nodes + j) for (j, name) in enumerate(group_names)),
    )
end
```

In `probe_pipeline`, compute it once after `groups = …` — `may_refer = referable(spec["nodes"], groups)` — and add `referable = may_refer` to **every** envelope the function returns (the empty-group early return, the build failure, and the success reply). Read the function top to bottom and count them: a reply without the key is what the first test catches.

- [ ] **Step 4: Run, watch it pass; mutation-check** — replace `==(typemax(Int))` with `!=(typemax(Int))`: the chain assertions must fail. Restore.

- [ ] **Step 5: Run `DashiBoard/test/runtests.jl`; commit**

```bash
git add DashiBoard/src DashiBoard/test/dashiboard.jl
git commit -m "probe: what each card and group may refer to without a loop"
```

---

### Task 3: The layout — header chips, a panel that folds, tabs in the new order

**Files:**
- Modify: `dashiboard-ui/src/components/SelectorField.tsx`, `dashiboard-ui/src/components/IRField.tsx:334-400` (the two `Collapsible` wrappers around `SelectorField` go), `dashiboard-ui/src/components/GroupsEditor.tsx` (the `SelectorField` call)
- Test: `dashiboard-ui/src/components/SelectorField.test.tsx`, `IRField.test.tsx`, `GroupsEditor.test.tsx`

**Interfaces — Produces:** `SelectorField` props gain `required?: boolean`. It renders its own label and fold; callers no longer wrap it.

Structure of the root, top to bottom:

```tsx
<div data-selector class="my-1 flex flex-col gap-1">
  <div class="flex flex-wrap items-center gap-1.5">            {/* header, always visible */}
    <button data-fold aria-expanded={open()} aria-controls={panelId} …>›</button>
    <span class="text-control-xs font-semibold text-primary">{label}{required ? "*" : ""}</span>
    <ul aria-label={`${label} selection`} class="flex min-w-0 flex-wrap gap-1">…chips…</ul>
  </div>
  {/* Task 4 puts the text box here */}
  <div data-panel id={panelId} hidden={!open()}>WRITES strip + tabs + rows</div>
</div>
```

- A chip: `<li data-chip={chipText(row)} tabIndex={-1}>` with the text, then `[data-move="earlier"]`, `[data-move="later"]` (list mode only), then `<button data-chip-remove aria-label={`remove ${chipText(row)}`}>×</button>`.
- `chipText(row) = `${row.kind}:${row.value}${row.chain.map((n) => `@${n}`).join("")}``. Export it from `SelectorField.tsx`; the pills in the panel use the same `@node@node` form (`data-case` keeps `"direct"` or the chain joined by `→`, which the existing tests read).
- `open` starts `false`. `KIND_ORDER = ["nodes", "groups", "cols"]`; `kinds()` additionally drops a kind whose `optionsOf(kind)` is empty.
- In single mode the chip is drawn too (it used to be hidden with the order strip), without the move buttons.
- The struck-through "missing" styling and its hover text stay in this task; Task 7 makes such references disappear.

- [ ] **Step 1: Write the failing tests** — add to `SelectorField.test.tsx` (the file's `mount(value, onChange)` and helpers `tab`, `row`, `sw` exist; panel rows are only reachable once the panel is open, so add `const open = (c: HTMLElement) => fireEvent.click(c.querySelector('[data-fold]')!);` and call it, followed by `await flush()`, at the start of every existing test that touches tabs or rows):

```tsx
describe('SelectorField, layout', () => {
  it('shows the name and the chips with the panel folded, in the notation that is typed', () => {
    const { container } = mount([{ cols: 'PRES', through: ['rescale', 'log'] }, { groups: 'weather' }]);
    expect(container.querySelector('[data-panel]')!.hasAttribute('hidden')).toBe(true);
    expect(container.querySelector('[data-fold]')!.getAttribute('aria-expanded')).toBe('false');
    expect([...container.querySelectorAll('[data-chip]')].map((c) => c.getAttribute('data-chip')))
      .toEqual(['cols:PRES@rescale@log', 'groups:weather']);
  });

  it('unfolds the panel from the button beside the name', async () => {
    const { container } = mount([]);
    fireEvent.click(container.querySelector('[data-fold]')!);
    await flush();
    expect(container.querySelector('[data-panel]')!.hasAttribute('hidden')).toBe(false);
    expect(container.querySelector('[data-fold]')!.getAttribute('aria-expanded')).toBe('true');
  });

  it('removes a value from its chip, which is the only way with the panel folded', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }, { cols: 'TEMP' }], (items) => { written = items; });
    fireEvent.click(container.querySelector('[data-chip="cols:PRES"] [data-chip-remove]')!);
    await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
  });

  it('orders the tabs nodes, groups, cols, and leaves out a kind with nothing to offer', async () => {
    const { container } = mount([]);
    open(container); await flush();
    expect([...container.querySelectorAll('[role=tab]')].map((t) => t.getAttribute('data-tab')))
      .toEqual(['nodes', 'groups', 'cols']);
    cleanup();
    const noGroups = { ...defs, group: { ...defs.group, enum: [] } } as Defs;
    const bare = render(() => <SelectorField itemNode={itemNode} defs={noGroups} label="inputs" value={[]} onChange={() => {}} />);
    open(bare.container); await flush();
    expect([...bare.container.querySelectorAll('[role=tab]')].map((t) => t.getAttribute('data-tab')))
      .toEqual(['nodes', 'cols']);
  });

  it('shows a lone selector its chip too, without the arrows', () => {
    const { container } = render(() => (
      <SelectorField single itemNode={itemNode} defs={defs} label="partition" value={{ nodes: 'split' }} onChange={() => {}} />
    ));
    const chip = container.querySelector('[data-chip="nodes:split"]')!;
    expect(chip).not.toBeNull();
    expect(chip.querySelector('[data-move]')).toBeNull();
    expect(chip.querySelector('[data-chip-remove]')).not.toBeNull();
  });
});
```

In `IRField.test.tsx`: the `rescale` form shows `[data-chip]`-less `inputs` with its name visible and its `[data-panel]` hidden, and the lone-selector round-trip test reads `nodes:` / `cols:PRES@rescale` from `[data-chip]` instead of the `writes` text. In `GroupsEditor.test.tsx`: a group with `[{ cols: 'TEMP' }]` shows `[data-chip="cols:TEMP"]` inside the opened group.

The single-mode test of 2026-09-18 "has no order strip and offers no second qualification" changes its first assertion: there is no `[data-move]`, and no `[data-add-case]` (the old `aria-label="partition order"` list no longer exists).

- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement** the structure above. In `IRField.tsx` the repeater's selector branch and `case "selector"` render `<SelectorField … required={props.required} />` directly, with no `Collapsible`. In `GroupsEditor.tsx` pass `label="columns"`.
- [ ] **Step 4: Run the whole suite.** Every test that reached a tab, a switch or the `writes` strip needs the panel opened first; fix them by opening the panel, never by changing what they assert about the document.
- [ ] **Step 5: Full UI verification; commit** — `git commit -m "selector: name and chips always visible, the panel folds, tabs nodes-groups-cols"`.

---

### Task 4: The text box

**Files:**
- Modify: `dashiboard-ui/src/components/SelectorField.tsx`
- Test: `dashiboard-ui/src/components/SelectorField.test.tsx`

**Interfaces — Consumes:** `step`, `suggestions`, `stageOf`, `emptyEntry` (Task 1); `rows()`, `write()`, `optionsOf()`, `chainOptions()`, `kinds()` (existing).

Markup, between the header and the panel:

```tsx
<div class="flex items-start gap-1.5">
  {/* Task 5 puts the help button here */}
  <div class="relative min-w-0 grow">
    <div class="flex flex-wrap items-center gap-1 rounded-sm border border-border px-1.5 py-1 focus-within:border-primary">
      <For each={tokens()}>{(t) => <span data-token class="rounded-sm bg-accent/60 px-1 font-mono text-control-xs">{t}</span>}</For>
      <input data-entry role="combobox" aria-expanded={entry().open} aria-controls={listId}
             aria-activedescendant={activeId()} aria-autocomplete="list" aria-label={`${label}, type a selection`}
             placeholder={tokens().length === 0 ? "nodes: name @node, then Enter" : ""}
             value={entry().text} onInput={…text…} onKeyDown={…} class="min-w-24 grow bg-transparent font-mono text-control-xs outline-none" />
    </div>
    <Show when={entry().open && !open()}>          {/* the dropdown, only while the panel is folded */}
      <ul id={listId} role="listbox" class="absolute z-10 mt-1 max-h-56 w-full overflow-y-auto rounded-sm border border-border bg-card p-1">…</ul>
    </Show>
  </div>
</div>
```

- `tokens()` = `[kind + ":", name, ...chain.map((n) => "@" + n)]`, skipping nulls.
- Key handling: `Tab` → `step({type:"tab"})`; if the step says `leave`, do **not** `preventDefault` (focus moves on); otherwise `preventDefault`. `Enter`, `Escape`, `ArrowDown`, `ArrowUp` → their inputs, `preventDefault`. `Backspace` → only when `entry().text === ""`. When a step emits a row: ignore it if `rows()` already holds the same kind, value and chain; else `write(single ? [row] : [...rows(), row])`.
- A suggestion, in the dropdown **and** as a panel row: `<li data-suggestion={value} role="option" id={…} aria-selected={highlighted}>` with the value, then `<button data-pick="direct">direct</button>` and `<button data-pick="through" disabled={chainOptions().length === 0}>through…</button>`. At the kind stage there are no buttons: clicking the row is `pick … how: "continue"`.
- **The box drives the open panel:** with the panel open, `openKind()` follows `entry().kind` when it is set; the rows shown are `suggestions(entry(), vocabulary())` when the entry is at the name stage (all of the kind's names when nothing is typed); the highlighted row carries `data-highlighted`. At the chain stage the panel shows the chain's node suggestions in place of the rows. No dropdown is rendered while the panel is open.

- [ ] **Step 1: Write the failing tests**

```tsx
describe('SelectorField, typed entry', () => {
  const box = (c: HTMLElement) => c.querySelector('[data-entry]') as HTMLInputElement;
  const type = async (c: HTMLElement, value: string) => { fireEvent.input(box(c), { target: { value } }); await flush(); };
  const key = async (c: HTMLElement, k: string) => { const e = fireEvent.keyDown(box(c), { key: k }); await flush(); return e; };
  const tokens = (c: HTMLElement) => [...c.querySelectorAll('[data-token]')].map((t) => t.textContent);

  it('writes the same document as the panel: kind, name, chain, Enter', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await type(container, 'c'); await key(container, 'Tab');
    await type(container, 'PRE'); await key(container, 'Tab');
    await type(container, '@resc'); await key(container, 'Tab');
    expect(tokens(container)).toEqual(['cols:', 'PRES', '@rescale']);
    await key(container, 'Enter');
    expect(written).toEqual([{ cols: 'PRES', through: ['rescale'] }]);
    expect(tokens(container)).toEqual(['cols:']);            // the kind stays for the next entry
    expect(box(container).value).toBe('');
  });

  it('lets TAB through when nothing is being typed, and keeps it while completing', async () => {
    const { container } = mount([]);
    expect(await key(container, 'Tab')).toBe(true);          // not prevented: focus moves on
    await type(container, 'c');
    expect(await key(container, 'Tab')).toBe(false);         // prevented: it completed `cols:`
  });

  it('shows a dropdown of matches while the panel is folded, and none when it is open', async () => {
    const { container } = mount([]);
    await type(container, 'c'); await key(container, 'Tab'); await type(container, 'TE');
    expect(container.querySelector('[role=listbox] [data-suggestion="TEMP"]')).not.toBeNull();
    open(container); await flush();
    expect(container.querySelector('[role=listbox]')).toBeNull();
  });

  it('drives the open panel: the tab follows the kind, the rows narrow, the highlight moves', async () => {
    const { container } = mount([]);
    open(container); await flush();
    await type(container, 'c'); await key(container, 'Tab');
    expect(container.querySelector('[role=tab][aria-selected="true"]')!.getAttribute('data-tab')).toBe('cols');
    await type(container, 'TE');
    const shown = [...container.querySelectorAll('[data-panel] [data-value]')].map((r) => r.getAttribute('data-value'));
    expect(shown.every((v) => v!.toLowerCase().includes('te'))).toBe(true);
    expect(container.querySelector('[data-panel] [data-highlighted]')!.getAttribute('data-value')).toBe(shown[0]);
  });

  it('gives the mouse the panel\'s two words in the list: direct finishes, through… asks for a node', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([], (items) => { written = items; });
    await type(container, 'c'); await key(container, 'Tab');
    fireEvent.click(container.querySelector('[data-suggestion="TEMP"] [data-pick="direct"]')!); await flush();
    expect(written).toEqual([{ cols: 'TEMP' }]);
    fireEvent.click(container.querySelector('[data-suggestion="PRES"] [data-pick="through"]')!); await flush();
    expect(tokens(container)).toEqual(['cols:', 'PRES']);
    expect(box(container).value).toBe('@');
    expect(container.querySelector('[data-suggestion="rescale"]')).not.toBeNull();
  });

  it('does not add the same value with the same chain twice', async () => {
    const written: SelectorItem[][] = [];
    const { container } = mount([{ cols: 'PRES' }], (items) => { written.push(items); });
    await type(container, 'c'); await key(container, 'Tab'); await type(container, 'PRES'); await key(container, 'Enter');
    expect(written).toEqual([]);
  });

  it('replaces the one item of a lone selector, and clears the box', async () => {
    let written: SelectorItem | undefined | null = null;
    const { container } = render(() => (
      <SelectorField single itemNode={itemNode} defs={defs} label="partition" value={{ cols: 'PRES' }} onChange={(item) => { written = item; }} />
    ));
    await type(container, 'c'); await key(container, 'Tab'); await type(container, 'TEMP'); await key(container, 'Enter');
    expect(written).toEqual({ cols: 'TEMP' });
    expect(tokens(container)).toEqual([]);
  });

  it('is a combobox to a screen reader', async () => {
    const { container } = mount([]);
    expect(box(container).getAttribute('role')).toBe('combobox');
    expect(box(container).getAttribute('aria-expanded')).toBe('false');
    await type(container, 'c');
    expect(box(container).getAttribute('aria-expanded')).toBe('true');
    expect(container.querySelector(`#${box(container).getAttribute('aria-activedescendant')}`)).not.toBeNull();
  });
});
```

`fireEvent.keyDown` returns `false` when `preventDefault` was called; the second test relies on it.

- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement** as specified above. The entry state is one signal, `const [entry, setEntry] = createSignal(emptyEntry)`; `vocabulary()` is a memo `{ kinds: kinds(), options: Object.fromEntries(kinds().map((k) => [k, optionsOf(k)])), chain: chainOptions() }`.
- [ ] **Step 4: Run; mutation-check the duplicate guard** (remove it: the "twice" test must fail) **and the TAB rule** (always `preventDefault`: the TAB test must fail).
- [ ] **Step 5: Full UI verification; commit** — `git commit -m "selector: a text box that walks the panel's steps from the keyboard"`.

---

### Task 5: Chips by keyboard, and a way to learn the keys

**Files:**
- Create: `dashiboard-ui/src/components/SelectorHelp.tsx`, `SelectorHelp.test.tsx`
- Modify: `dashiboard-ui/src/components/SelectorField.tsx`; Test: `SelectorField.test.tsx`

**Interfaces — Produces:** `SelectorHelp(props: { single?: boolean })` — a `<button data-help aria-label="how to type a selection" aria-expanded>?</button>` and, when open, a `<div role="note">` listing: `c`/`g`/`n` then Tab — choose cols, groups or nodes · type, then Tab — take the top match (↑ ↓ to choose) · `@` — pass through a node; repeat for a chain · Enter — add it · Backspace — undo the last part · Esc — close, then clear · ← from the empty box — reach the chips; there Delete removes and (list fields only) Alt+← / Alt+→ reorder. Esc or a second click closes it.

Chip keys, on a focused `[data-chip]` (`tabIndex={-1}`, focused programmatically): `ArrowLeft`/`ArrowRight` move focus between chips (`ArrowRight` on the last returns to the box); `Delete`/`Backspace` remove the chip and focus the previous one, or the box; `Alt+ArrowLeft`/`Alt+ArrowRight` call `reorder` (not in single mode) and keep focus on the moved chip; `Escape`/`Tab` return to the box. From the box: `ArrowLeft` at caret position 0 with an empty entry (`stageOf` is `kind`, no text), or `Shift+Tab` in that same state with at least one chip, focuses the last chip and is prevented.

- [ ] **Step 1: Write the failing tests**

```tsx
describe('SelectorField, chips by keyboard', () => {
  const box = (c: HTMLElement) => c.querySelector('[data-entry]') as HTMLInputElement;
  const chips = (c: HTMLElement) => [...c.querySelectorAll('[data-chip]')] as HTMLElement[];

  it('reaches the chips from the empty box, walks them, and comes back', async () => {
    const { container } = mount([{ cols: 'PRES' }, { cols: 'TEMP' }]);
    box(container).focus();
    fireEvent.keyDown(box(container), { key: 'ArrowLeft' }); await flush();
    expect(document.activeElement).toBe(chips(container)[1]);
    fireEvent.keyDown(chips(container)[1], { key: 'ArrowLeft' }); await flush();
    expect(document.activeElement).toBe(chips(container)[0]);
    fireEvent.keyDown(chips(container)[0], { key: 'Escape' }); await flush();
    expect(document.activeElement).toBe(box(container));
  });

  it('removes the focused chip with Delete, and moves it with Alt and an arrow', async () => {
    let written: SelectorItem[] | null = null;
    const { container } = mount([{ cols: 'PRES' }, { groups: 'weather' }, { cols: 'TEMP' }], (items) => { written = items; });
    box(container).focus();
    fireEvent.keyDown(box(container), { key: 'ArrowLeft' }); await flush();
    fireEvent.keyDown(chips(container)[2], { key: 'ArrowLeft', altKey: true }); await flush();
    expect(written).toEqual([{ cols: 'PRES' }, { cols: 'TEMP' }, { groups: 'weather' }]);
    fireEvent.keyDown(document.activeElement!, { key: 'Delete' }); await flush();
    expect(written).toEqual([{ cols: 'PRES' }, { groups: 'weather' }]);
  });

  it('does not take the arrow while something is being typed', async () => {
    const { container } = mount([{ cols: 'PRES' }]);
    fireEvent.input(box(container), { target: { value: 'c' } }); await flush();
    box(container).focus();
    fireEvent.keyDown(box(container), { key: 'ArrowLeft' }); await flush();
    expect(document.activeElement).toBe(box(container));
  });
});
```

`SelectorHelp.test.tsx`: closed by default; a click opens a `role="note"` that mentions `Tab`, `@`, `Enter` and `Alt`; with `single` it does not mention reordering; `Escape` closes it; the button is reachable (`tabIndex` not `-1`). In `SelectorField.test.tsx`: the help button is the element before the text box, and the empty box shows the placeholder `nodes: name @node, then Enter`.

- [ ] **Step 2: Run, watch them fail.** — [ ] **Step 3: Implement.** — [ ] **Step 4: Run; full UI verification.**
- [ ] **Step 5: Commit** — `git commit -m "selector: chips by keyboard, and a help button that lists the keys"`.

---

### Task 6: A picker offers only what its item may refer to

**Files:**
- Modify: `dashiboard-ui/src/stores.ts` (`ProbeStore.referable`, `emptyProbe`), `dashiboard-ui/src/probe.ts` (`usableProbe`), `dashiboard-ui/src/ir.ts` (`onlyOptions`), `dashiboard-ui/src/left-tabs/processing.tsx:156-160` (`defsForNode`), `dashiboard-ui/src/components/GroupsEditor.tsx` (the `defs=` passed to `SelectorField`)
- Test: `ir.test.ts`, `probe.test.ts`, `processing.test.tsx`, `GroupsEditor.test.tsx`

**Interfaces — Produces:**

```ts
export type Referable = { nodes: string[]; groups: string[] };
// ProbeStore gains:  referable: { nodes: Referable[]; groups: Record<string, Referable> } | null
/** `defs` with one vocabulary cut down to the names in `allowed`, in its own order. */
export function onlyOptions(defs: Defs, key: string, allowed: readonly string[]): Defs;
```

`defsForNode(index)`: when `probe.referable?.nodes.length === state.nodes.length`, return `onlyOptions(onlyOptions(defs, "node", r.nodes), "group", r.groups)` with `r = probe.referable.nodes[index]`; otherwise today's `withoutOption(defs, "node", self)`. The length check is what keeps a reply about an older document (a card just added or removed) from being read against the wrong cards. `GroupsEditor` does the same with `probe.referable?.groups[name]`, falling back to `withoutOption(defs, "group", name)`.

- [ ] **Step 1: Write the failing tests**

`ir.test.ts`:
```ts
it('onlyOptions keeps the allowed names of one vocabulary, in its own order, and leaves the rest', () => {
  const defs = { node: { type: 'string', enum: ['a', 'b', 'c'] }, col: { type: 'string', enum: ['x'] } } as Defs;
  const cut = onlyOptions(defs, 'node', ['c', 'a', 'zz']);
  expect(cut.node.enum).toEqual(['a', 'c']);
  expect(cut.col).toBe(defs.col);
  expect(onlyOptions(defs, 'missing', ['a'])).toBe(defs);
});
```

`probe.test.ts`: `usableProbe({ valid: true })` has `referable: null`; a reply with `referable: { nodes: [...], groups: {...} }` keeps it; a malformed one (`referable: 3`) becomes `null`.

`processing.test.tsx`:
```tsx
describe('what a card is offered', () => {
  it('leaves out the nodes that depend on it once the server has said which', async () => {
    const rescale = { type: 'rescale', method: { type: 'zscore' }, inputs: [] };
    importCards({ nodes: [{ id: 'a', card: rescale }, { id: 'b', card: rescale }, { id: 'c', card: rescale }], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('#node-id-2')).not.toBeNull());
    const offered = (at: number) => {
      const card = [...container.querySelectorAll('details')].filter((d) => d.querySelector('[data-card-title]'))[at];
      const field = card.querySelector('[data-selector]')!;
      fireEvent.click(field.querySelector('[data-fold]')!);
      return [...field.querySelectorAll('[data-panel] [data-value]')].map((e) => e.getAttribute('data-value'));
    };
    expect(offered(0)).toEqual(['b', 'c']);                       // before any answer: everything but itself
    PROBE_STORE[1]((d) => { d.referable = { nodes: [{ nodes: [], groups: [] }, { nodes: ['a'], groups: [] }, { nodes: ['a', 'b'], groups: [] }], groups: {} }; });
    await flush();
    expect(offered(0)).toEqual([]);                                // b and c depend on a
    expect(offered(2)).toEqual(['a', 'b']);
  });
});
```
(`nodes` is the first tab, so the opened panel shows node names.) `GroupsEditor.test.tsx`: a group whose `referable` entry omits a node is not offered it.

- [ ] **Step 2: Run, watch them fail.** — [ ] **Step 3: Implement.** — [ ] **Step 4: Run; mutation-check the length guard** (remove it, and make the second test set a `referable` of the wrong length: the fallback assertion must fail).
- [ ] **Step 5: Full UI verification; commit** — `git commit -m "selector: offer an item only what it may refer to, as the server reports it"`.

---

### Task 7: References to things that are not there are removed, and said

**Files:**
- Modify: `dashiboard-ui/src/stores.ts` (after `forEachSelector`), `dashiboard-ui/src/left-tabs/loading.tsx` (after `pruneFilters(next)`), `dashiboard-ui/src/left-tabs/processing.tsx` (`loadCards`, and the notice at the top of the tab), `dashiboard-ui/src/components/SelectorField.tsx` (the struck-through chip goes)
- Test: `stores.test.ts`, `loading.test.tsx`, `processing.test.tsx`, `SelectorField.test.tsx`

**Interfaces — Produces:**

```ts
export type DroppedReference = { what: string; where: string };   // "cols:PRES", "r" / "group bills"
/** Remove references to columns the table lacks and to nodes and groups the document lacks. */
export function pruneReferences(columns: readonly string[] | null): DroppedReference[];
export const [droppedReferences, setDroppedReferences]: [Accessor<DroppedReference[]>, Setter<DroppedReference[]>];
```

`columns === null` or empty means no table is loaded: column references are left alone. Nodes and groups are judged against the document itself. A chain loses a missing step and keeps the rest (what `dropName` does when a node is removed). `forEachSelector`'s callback gains a second argument, `where: string` — the card's id (or `card N`), or `group <name>` — which `removeGroup`, `renameGroup`, `setNodeId` and `removeNode` ignore.

- [ ] **Step 1: Write the failing tests** — `stores.test.ts`:

```ts
describe('pruneReferences', () => {
  const doc = () => ({
    nodes: [
      { id: 'r', card: { type: 'rescale', inputs: [{ cols: ['TEMP', 'GONE'] }, { nodes: 'ghost' }, { cols: 'PRES', through: ['ghost', 'r2'] }], partition: { groups: 'nogroup' } } },
      { id: 'r2', card: { type: 'rescale', inputs: [{ groups: 'g' }] } },
    ],
    groups: { g: [{ cols: 'GONE' }, { cols: 'TEMP' }] },
  });
  it('removes what is not in the table or the document, keeps the rest, and says what and where', async () => {
    const s = await import('./stores');
    s.importCards(doc()); await flush();
    const dropped = s.pruneReferences(['TEMP', 'PRES']); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ cols: 'TEMP' }, { cols: 'PRES', through: ['r2'] }]);
    expect('partition' in out.nodes[0].card).toBe(false);
    expect(out.groups.g).toEqual([{ cols: 'TEMP' }]);
    expect(dropped).toEqual([
      { what: 'cols:GONE', where: 'r' }, { what: 'nodes:ghost', where: 'r' }, { what: '@ghost', where: 'r' },
      { what: 'groups:nogroup', where: 'r' }, { what: 'cols:GONE', where: 'group g' },
    ]);
  });
  it('judges no column while no table is loaded', async () => {
    const s = await import('./stores');
    s.importCards(doc()); await flush();
    const dropped = s.pruneReferences(null); await flush();
    expect(s.exportCards().nodes[0].card.inputs[0]).toEqual({ cols: ['TEMP', 'GONE'] });
    expect(dropped.map((d) => d.what)).toEqual(['nodes:ghost', '@ghost', 'groups:nogroup']);
  });
  it('leaves a loop alone: both of its references exist', async () => {
    const s = await import('./stores');
    s.importCards({ nodes: [{ id: 'a', card: { type: 'rescale', inputs: [{ nodes: 'b' }] } }, { id: 'b', card: { type: 'rescale', inputs: [{ nodes: 'a' }] } }], groups: {} });
    await flush();
    expect(s.pruneReferences(['TEMP'])).toEqual([]);
  });
});
```

`loading.test.tsx`: with a card reading `{cols:'GONE'}` in the cards store, a load whose summaries lack `GONE` leaves `droppedReferences()` holding `{ what: 'cols:GONE', … }` and the card without the reference. `processing.test.tsx`: loading a cards document that names a node it does not have shows `[data-dropped-references]` whose text starts `References removed — not in the table or the document:` and names it; its dismiss button (`aria-label="dismiss"`) removes the notice; the document handed to the probe no longer holds the reference. `SelectorField.test.tsx`: no `[data-missing]` and no `line-through` remain — delete the tests of the struck-through chip, which describe behaviour that no longer exists.

- [ ] **Step 2: Run, watch them fail.**

- [ ] **Step 3: Implement** — in `stores.ts`:

```ts
export type DroppedReference = { what: string; where: string };
/** What the last table or document load removed, for the Process tab to say. Transient. */
export const [droppedReferences, setDroppedReferences] = createSignal<DroppedReference[]>([]);

/**
 * Remove references to columns the loaded table lacks and to nodes and groups the document
 * lacks, and return them. No table loaded means columns cannot be judged, so they stay. A
 * reference that exists is never removed here, even when it makes a loop.
 */
export function pruneReferences(columns: readonly string[] | null): DroppedReference[] {
  const dropped: DroppedReference[] = [];
  setCards((draft) => {
    const present: Record<string, Set<string> | null> = {
      cols: columns && columns.length > 0 ? new Set(columns) : null,
      nodes: new Set(draft.nodes.map((node) => node.id ?? "")),
      groups: new Set(Object.keys(draft.groups)),
    };
    forEachSelector(draft, (item, where) => {
      const out: Selector = { ...item };
      for (const kind of ["cols", "nodes", "groups"] as const) {
        const known = present[kind];
        if (known === null || !(kind in out)) continue;
        const values = Array.isArray(out[kind]) ? (out[kind] as string[]) : [out[kind] as string];
        const kept = values.filter((value) => known.has(value) || (dropped.push({ what: `${kind}:${value}`, where }), false));
        if (kept.length === 0) delete out[kind];
        else out[kind] = kept.length === 1 ? kept[0] : kept;
      }
      if (Array.isArray(out.through)) {
        out.through = out.through.filter((step) => present.nodes!.has(step) || (dropped.push({ what: `@${step}`, where }), false));
        if (out.through.length === 0) delete out.through;
      }
      return "cols" in out || "groups" in out || "nodes" in out ? out : null;
    });
  });
  return dropped;
}
```

`forEachSelector` passes `where`: `node.id || `card ${index + 1}`` for a card, `group ${name}` for a group. An item that loses its value also loses its chain without the chain's steps being reported — the test above expects `@ghost` from the *third* item only, whose value `PRES` survives.

Callers: `loading.tsx`, right after `pruneFilters(next)`: `setDroppedReferences(pruneReferences(next.map((s) => s.name)))`. `processing.tsx`, in `loadCards`: the document has to be pruned *before* it is stored and probed, because a store write cannot be read back in the same tick. So `pruneReferences` takes an optional second argument, `target?: CardsStore`: given one, it prunes that plain object in place instead of the store (one implementation, two targets — wrap the body in a function of `draft` and call it with `target` or inside `setCards`). `loadCards` calls `setDroppedReferences(pruneReferences(columns, document))` with the loaded table's column names (or `null`), then `importCards(document)`, then probes `document` as it does today. Add a store test for the `target` form: the plain object is pruned and the store is untouched.

The notice, at the top of `Cards`' JSX, in the dress of `[data-dropped-filters]` (`filtering.tsx:55-72`):

```tsx
<Show when={droppedReferences().length > 0}>
  <div data-dropped-references class="mx-3 mb-2 flex items-start gap-2 rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground">
    <span class="min-w-0 flex-1">
      References removed — not in the table or the document:{" "}
      <span class="font-mono">{droppedReferences().map((d) => `${d.what} from ${d.where}`).join(", ")}</span>
    </span>
    <button type="button" aria-label="dismiss" onClick={() => setDroppedReferences([])} class="grid h-4 w-4 shrink-0 place-items-center rounded-sm text-muted-foreground hover:bg-secondary hover:text-foreground">×</button>
  </div>
</Show>
```

- [ ] **Step 4: Run; mutation-check "no table, no judgment"** (treat `null` as an empty set: the second store test must fail).
- [ ] **Step 5: Full UI verification; commit** — `git commit -m "references to what is not there are removed, and said in an amber notice"`.

---

## Hand-over

After Task 7: the four UI commands and `DashiBoard/test/runtests.jl` on the final tree; `git grep -n "data-missing\|line-through" dashiboard-ui/src/components/SelectorField.tsx` returns nothing. Against a running server through the Vite proxy, `POST /probe-pipeline` for a three-card chain answers `referable` as in Task 2's test. The owner's browser checks are in the spec, §11; the todo gains a line for this work.
