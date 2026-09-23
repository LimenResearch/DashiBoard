# Presets — starting values for the fields cards share

Why: every card of a pipeline usually partitions the same way, orders by the same columns and
groups by the same keys. Today each is filled in by hand, card after card, although the values are
the author's one decision. Owner, 2026-09-23: a **Presets** panel beside `Add group` / `Add card`
where those shared fields are set once; a card created afterwards starts with them. Decided in the
same conversation: the fields come from the IR, the presets live in the browser, and only cards
created *after* a preset is set carry it. Baseline: `ds-DashiUI` @ `67b1803` plus the working tree
of 2026-09-23. Only `dashiboard-ui/` changes.

## 1. What a preset is

A value for one field, in exactly the shape a card's field holds — one selector item, or a list of
them. Nothing else: no card type, no condition.

```ts
export type PresetStore = { [field: string]: SelectorItem | SelectorItem[] };
export const PRESETS_STORE = persisted<PresetStore>("dashi.presets", {});
```

`sessionStorage`, through the same `persisted` the document uses, and for the same reason: a
reload must not lose the author's setting, and two tabs editing two pipelines must not share one.
A preset is **not** part of the document — it is never saved, downloaded or sent, and a pipeline
file carries only the values already copied into its cards. Absent, or an empty list, means no
preset for that field.

## 2. Which fields take a preset

Derived from the card IR, never from a list in the code:

> A top-level property of a card type whose value is a **selector** — `$defs/variable` (one) or
> `$defs/variables` / `nonempty_variables` (a list) — that is not `inputs`, `targets` or `input`,
> and that **at least two card types have**.

- The exclusions are what a card *operates on*: naming them once for the whole pipeline would be
  naming the pipeline's one job, which is not what a card is.
- The two-card floor is what makes a preset worth the name; a selector field unique to one card
  type is that card's own business.
- Only top-level: `glm`'s `formula.target` is nested inside the operation it defines.

Measured on the IR the server serves today (10 card types):

| field | card types | kind |
|---|---|---|
| `partition` | 6 | one |
| `group_by` | 3 | list |
| `order_by` | 3 | list |
| `weights` | 2 | one |

(`inputs` 4, `targets` 3, `input` 2 — excluded by name. No other selector field reaches two.)

```ts
export type PresetField = { key: string; single: boolean; node: IRNode };
/** The fields a preset may be set for, most widely shared first, then by name. */
export function presetFields(cards: { [type: string]: IRNode }, defs: Defs): PresetField[];
```

`single` is `true` for a `variable` field. A field that is one value in one card type and a list in
another would have no single shape to store; `presetFields` treats such a field as a list and the
tests assert that today's IR has no such case, so a future one is found by a failing test rather
than by a wrong value in a document.

## 3. The panel

A third button in the sticky row, right of `Add card`:

```
[Add group] [Add card] [Presets 2]
```

- The count is the number of fields that carry a preset; with none it reads `Presets`.
- It opens a card-shaped panel through the `Add card` menu's placement rule — below the button
  when the view has room, above it otherwise — as `role="dialog"`, closed by Esc, by a click
  outside, and by the button itself. The first field takes focus.
- One `SelectorField` per `presetFields` entry, `single` where the field takes one value, labelled
  by the field name. Each writes its field of `PRESETS_STORE`; clearing a field removes the key.
- **Vocabulary:** the whole of `defs` — every column, node and group. A preset is not a card, so
  `referable` does not apply, and a card created from it is appended last and can refer to
  anything that exists. `through…` narrows by the usual `chainFor`, so a chain offered here is one
  the server can produce.

## 4. Applying, at creation only

Picking a type in the `Add card` menu builds the card as it does today — the IR's own defaults —
and then copies in each preset **the chosen type actually has a field for**. A preset fills a
field the IR left empty — `group_by` and `order_by` default to `[]`, which is emptiness, not a
choice — and never overwrites a value the IR actually declares. A card type with none of the
preset fields is created exactly as before.

The value lands as an ordinary value: nothing marks it, nothing links back, and editing or
clearing it is what it looks like. Changing a preset afterwards leaves every existing card alone —
the author's work is never rewritten under their hands.

`Add group` is untouched: a group is a list of columns with no fields to preset.

## 5. Presets follow the names they hold

A preset may name a node or a group. The document's own references are kept in step when one is
renamed or removed (`renameIn` / `dropName` through `forEachSelector`), and the presets get the
same treatment, from the same two helpers, in `renameGroup`, `setNodeId`, `removeGroup` and
`removeNode`. So a rename carries the preset with it, a removal drops the name from it (a chain
losing one step keeps the rest), and the next card never starts from a reference to something the
document no longer has.

Columns are not judged here: `pruneReferences` already answers that for the document when a table
lands, and a preset naming a column the table lacks simply produces a card the existing amber
notice cleans up on the next load.

## 6. Tests

- `presets.test.ts` — `presetFields` on the real `card-ir.json`: exactly `partition`, `group_by`,
  `order_by`, `weights`, in that order, with `single` right for each; `inputs`, `targets`, `input`
  absent; a field only one card type has is absent; no field is a list in one type and one value in
  another.
- `stores.test.ts` — a preset naming a node follows `setNodeId`, is dropped by `removeNode`, and
  the same for a group through `renameGroup` / `removeGroup`; a preset chain loses only the removed
  step. The store survives a reload (the `persisted` round trip the other stores are tested by).
- `Presets.test.tsx` — closed until asked; the button's count; Esc, an outside click and a second
  click close it; a field writes the store and clearing removes the key; the fields drawn are
  `presetFields`.
- `processing.test.tsx` — a card created after `partition` is preset carries it; a card type
  without `partition` does not; a preset set after a card exists leaves that card alone; with no
  preset the card is exactly what it is today.

## 7. Out of scope

Presets for fields that are not selectors (`suffix`, `output`, `method`, `n_components`); applying
a preset to cards that already exist; presets in the saved pipeline or anywhere the server sees;
per-card-type presets; and any change to `Pipelines/` or `DashiBoard/src`.

## 8. Process

Bounded and self-contained: tests first, one commit per task, the owner reviews. Browser check:
set `partition` and `order_by` in Presets, add a `rescale` (takes both) and a `window_function`
(takes `order_by`, not `partition`) and see each start filled in; rename the node a preset points
at and see the preset follow; clear a preset and see the next card start empty.
