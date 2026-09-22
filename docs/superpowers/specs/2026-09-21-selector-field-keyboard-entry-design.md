# SelectorField — typed entry beside the mouse panel

Why: the variable picker is mouse-only. The team leader works from the keyboard and first asked
for a combobox; the owner prefers the current panel of switches. Agreed in a meeting and detailed
with the owner on 2026-09-21: **one component with two ways in — the panel, essentially as it is,
and a typed entry that walks the same steps — producing the same document.** Notes from the
meeting: `.superpowers/sdd/SelctorFIeld-refactor/brainstorm.md`. Baseline: `ds-DashiUI` @
`0a332eb`. `dashiboard-ui/` and `DashiBoard/src` change; `Pipelines/` does not.

## 1. Anatomy

```
› inputs*  [cols:PRES@sp ← → ×] [groups:bills ← → ×]             always
  (?) ┌────────────────────────────────────────────────────┐     visible
      │ [cols:] [bill_length] [@impute] @zsc▏              │
      └────────────────────────────────────────────────────┘
  ───────────────────────────────────────────────  folded by default
  WRITES {cols = "PRES", through = "sp"}
  [ nodes | groups 1 | cols 1 ]   … the panel of switches …
```

- **Header line:** the fold button where it is today, the field name, and the chips beside it
  (they wrap). A chip reads as it is typed — `cols:PRES@sp`, `cols:PRES@impute@zscore` — and
  carries `←`, `→` and `×`. The `×` is new: with the panel folded there was no way to remove a
  value by mouse.
- **Text box:** full width, under the header, with a `?` button before it (§5).
- **Fold:** only `WRITES` and the tabbed panel fold. Folded by default.
- **Every field that takes a selector looks like this**, the single-column ones included
  (`partition`, `weights`, `input`): today they show no chips at all, because chips live in the
  order strip and single mode hides it. Their chip has no arrows.
- **Tabs read `nodes`, `groups`, `cols`**, in that order: the further a document grows, the more
  it is written in nodes and groups. A tab with nothing to offer is not drawn. The panel's
  qualification pills say `@sp` rather than `through sp`: one notation everywhere.

## 2. The typed entry

An entry is **kind → name → optional chain → finish**, the steps the panel takes.

```
typing:    [cols:] [bill_length] [@impute] @zsc▏
after TAB: [cols:] [bill_length] [@impute] [@zscore] ▏
```

| input | effect |
|---|---|
| focus | the list opens on the kinds that have something: `nodes:`, `groups:`, `cols:` (revised 2026-09-22: the list always shows while the box is in hand; `:` alone asks for it too) |
| `c` TAB | token `cols:`; the list shows every column |
| text | the list narrows: names containing the text, those starting with it first, each in the server's order |
| Up / Down | move the highlight in the list |
| TAB, something typed or a highlight moved | the highlighted match (the top one by default) becomes a token |
| TAB, nothing typed | leaves the field, as TAB does everywhere, whatever the list shows — also right after ENTER; Shift+TAB always goes back |
| after a name | the list shows the nodes a chain may pass through — **only those that read the value**, from what the probe says each node reads (`through.ts`); `@` is optional |
| `imp` TAB | token `@impute`; the list continues the chain with the nodes that read what `impute` produced, in the order typed |
| ENTER | the entry is finished: a chip appears, name and chain clear, **the kind token stays** and its names are on offer |
| Backspace, nothing typed | removes the last token whole; the kind goes last |
| Esc | closes the list; pressed again, clears the entry |

- Only names on offer become tokens, so a name with spaces or `@` in it is harmless and a typo
  cannot be entered. ENTER on a name with no `@` means *direct*.
- ENTER with nothing accepted beyond the kind does nothing.
- **Mouse, in the list:** each suggested name carries two small buttons, **direct** and
  **through…** — the panel's words. *direct* is ENTER. *through…* accepts the name, adds `@` and
  lists the nodes. A suggested node carries the same pair: finish here, or through another.
- **Single mode:** ENTER replaces the field's one item and clears the box entirely, kind
  included — there is nothing more to add.

## 3. The box and the panel are one list

Panel open: the panel *is* the suggestion list. The kind token selects the tab; text narrows its
rows; Up/Down move a highlight through them; no second dropdown appears. Clicking a switch in
the panel works as today and does not touch the box.

Panel folded: the same rows appear in a dropdown under the box while an entry is in progress.

## 4. Chips by keyboard

Left arrow or Shift+TAB from an empty box moves focus onto the last chip. On a chip: Delete or
Backspace removes it; Alt+← / Alt+→ move it earlier / later; ← / → walk between chips; Esc or
TAB returns to the box. Single mode: remove only.

## 5. Teaching it

- The `?` button before the box is reachable by TAB and opens a small panel listing the keys of
  §2 and §4. A hover tip alone would be out of reach for exactly the people this is for.
- The empty box shows one complete example as its placeholder: `nodes: name @node`, then Enter.

## 6. What a card may refer to

Today a card is offered every node except itself, in the `nodes` tab and at every `@`. Choosing
one that depends on this card makes a loop, which the server refuses for the whole document: the
picker offers choices that cannot end well. The same holds for groups, in both directions (a
card reading a group that reads a node downstream of the card).

**Rule:** an item — card or group — is offered every node and group except itself and what
depends on it, directly or not. By dependency, never by position in the list: cards run in
dependency order.

**Where:** the server. The probe reply gains `referable`, computed from
`Pipelines.dependency_graph` (which builds without sorting, so it answers for a looped document
too): for each card, by index, and each group, by name, `{nodes: [...], groups: [...]}`. The UI
narrows each picker's `node` and `group` vocabularies with it, the way `withoutOption` already
removes an item's own name; until a probe has answered — or when the graph cannot be built (two
cards with one name) — it falls back to today's "everything but itself". The browser does not
rebuild the graph.

## 6b. References to things that are not there are removed, and said

Owner, 2026-09-21: a reference that is no longer on offer is removed, with an amber notice that
can be closed — what already happens to a filter on a column the newly loaded table lacks
(`pruneFilters`, `[data-dropped-filters]`). The struck-through chip with its own remove button
goes: there is nothing left for it to show.

- **What is removed:** a reference to a column the loaded table does not have, or to a node or
  group the document does not have — in a card's selector fields, a lone selector, a group, and
  in `through` chains (a chain loses the step, as it does today when a node is removed).
- **When:** when a table lands, and when a cards document is loaded (before it is asked about).
  Inside the UI nothing else can create such a reference: removing or renaming a node or group
  already carries its references with it.
- **No table, no judgment:** with no table loaded the columns are unknown, so column references
  stay, as filters do.
- **The notice:** amber, at the top of the Process tab, closable, naming what went and from
  where — "References removed — not in the table or the document: `PRES` from `r`, `ghost`
  from group `bills`". Transient, like the filters' notice.
- **Not removed: a reference that exists but would make a loop.** `referable` (§6) only narrows
  what is *offered*. A loaded document with a loop keeps its references: the two sides of a
  loop are each other's downstream, so removing "what is not on offer" would cut both and
  decide for the author which dependency was the mistake. The loop is said next to Run with its
  members named, and the author cuts one side.

## 7. What does not change

- The document model (`selector.ts`: items, rows, `expand`, `collapse`). An entry emits exactly
  the row a click in the panel emits, so the document is the same whichever way it was made.
- The same value under two qualifications is two entries.
- `GroupsEditor` uses the component and gains the text box with it.
- No resolved column name is computed in the browser.

## 8. How it is built

- **`selectorEntry.ts`** — the grammar as a pure state machine: state
  `{kind?, name?, chain[], text}`, and `step(state, input, vocabulary) → state | emit(row)` for
  inputs `type`, `tab`, `at`, `enter`, `backspace`, `escape`, `pick(direct|through)`. No DOM: §2
  is tested as data, a case per table row.
- **`SelectorField`** — rearranged around it, with the combobox roles (`role="combobox"`,
  `aria-expanded`, `aria-controls`, `aria-activedescendant`, a `listbox` of `option`s), so a
  screen reader announces the suggestions. It takes over its own folding: the always-visible
  part cannot sit inside the `Collapsible` that `IRField` wraps it in today.
- **Server** — `referable` in the probe reply (`DashiBoard/src/handlers.jl`), with request tests.

## 9. Tests

- `selectorEntry.test.ts`: every row of §2; matching order; `@` with no nodes on offer; ENTER
  with only a kind; single mode clears the kind; a name containing a space and one containing
  `@` round-trip.
- `SelectorField.test.tsx`: chips in the header with `@` notation, `×` removes, arrows reorder;
  the box drives the open panel (tab follows the kind, rows narrow) and a dropdown appears when
  folded; *direct* / *through…* buttons; chips by keyboard (§4); TAB leaves an idle box;
  empty tabs not drawn, order `nodes`, `groups`, `cols`; the existing document-contract tests
  (case C, case E, chain order, no empty item) unchanged; single mode shows its chip.
- `IRField.test.tsx`, `GroupsEditor.test.tsx`: the header and box are visible with the panel
  folded; a lone selector field shows its chip.
- `DashiBoard/test/dashiboard.jl`: `referable` for a chain `a → b → c` (a is offered nothing
  downstream, c is offered a and b), through a group, for a looped document, and absent when two
  cards share a name.
- `processing.test.tsx`: a card's picker is not offered a node downstream of it once the probe
  has answered.
- `stores.test.ts`: `pruneReferences` removes a missing column, node and group from list
  selectors, lone selectors, groups and chains, and says what and where; keeps everything with
  no table loaded; leaves a loop's references alone. `loading.test.tsx` and
  `processing.test.tsx`: the amber notice appears after a table or a document that orphans a
  reference, names it, and closes.

## 10. Out of scope

The GLM formula line (`bill_length @impute @zscore + flippers @impute * species`): a different
control, for a field the server does not describe yet. One term of it is exactly one entry of
this box, so the grammar stays compatible. Also out: pasting a whole selector as text; which
nodes a chain can *meaningfully* pass through (a card with no `suffix`,
`2026-09-18-through-chain-validation-design.md`); any change to `Pipelines/`.

## 11. Process

TDD throughout; the entry model first, since everything else reads it. Side branch and worktree,
one commit per task, the owner reviews and merges. Comments say what a passage is for, briefly.
Owner's browser checks at the end: the keyboard walk of §2 on `inputs`; the same on `partition`;
chips by keyboard; the box driving the open panel; a card not being offered a node downstream
of it.
