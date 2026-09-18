# Verdicts — amber until asked, then green or red

Why: with the probe finally reaching the server from a browser (PR #170), the Process tab paints
red as soon as an item exists — a raw schema message in a banner at the top of the left column,
the same message on the card, an orange dot — before the author has asked anything. That
overwhelms, and it erases the difference between amber and red. Decided with the owner on
2026-09-17: **an item is amber until its first Confirm; Confirm turns it green or red; an edit
returns it to amber; red lives on the item; the only top-level signal is a one-line pointer next
to Run pipeline.** Baseline: `sdd/post-smoke` @ `6caf0d7`. No Julia change.

## 1. The three states

| dot | meaning | when |
|---|---|---|
| **amber** | not yet asked — new, or edited since the last verdict | default; after any edit of the item |
| **green** | asked, and the server found nothing wrong | Confirm passed on this exact content |
| **red** | asked, and the server found something wrong | Confirm (or a Run) reported an error for this exact content |

Rules:
- A verdict is bound to the item's **content signature** (`JSON.stringify` of the whole node —
  its id is part of what is checked — or of the group's selector list), exactly as the green
  mark is today. Green *and* red expire on edit — an edit invalidates the verdict, so the item
  goes amber and its findings disappear until the next Confirm. Nothing is "still wrong" by
  memory. The signature is taken from a **plain snapshot made before any request**, never from a
  live store proxy: an edit made while Confirm or a Run is in flight must leave the item unasked,
  not stamp it with an answer about content the server never saw.
- **Warnings never change the dot.** An overwrite warning renders amber *inside* the item, live,
  as now; a green item with a warning stays green.
- **The continuous probe keeps running** (it feeds the vocabulary of resolved names, the
  warnings, and the pointer of §3) but its errors no longer paint the item: no red findings on a
  card or group before Confirm, no orange dot from a live error. The `liveError` term added on
  2026-09-16 goes.
- **Run is allowed** with amber or red items; a failed run's issues are a verdict like Confirm's:
  each pointed item gets **red** with its findings, bound to its current signature.

## 2. Where verdicts live

`stores.ts` replaces the confirmations record with a **verdicts** record, persisted under
`dashi.verdicts` (the `dashi.confirmations` key is no longer written; a stale one is ignored):

```ts
type Verdict = { signature: string; verdict: "confirmed" | "rejected"; findings: Incompleteness[] };
recordVerdict(key: string, value: unknown, verdict: "confirmed" | "rejected", findings?: Incompleteness[]): void
verdictOf(key: string, value: unknown): Verdict | null   // null when none, or the signature no longer matches
forgetVerdict(key: string): void
forgetAllVerdicts(): void  // not exposed in the UI; tests and a future "new document"
```

Keys stay `node:<index>` and `group:<name>`. Removing a card slides the verdicts of the cards
behind it down one, finding pointers included, so an answer follows its card; the signature check
stays as the safety net. Removing a group forgets its verdict (a later same-name, same-content
group must not inherit it); renaming a group moves the verdict to the new name (the content is
unchanged). `isConfirmed(key, value)` remains as `verdictOf(key, value)?.verdict === "confirmed"`
for existing callers. Findings travel with the
verdict so a reload shows the same red and the same messages; they vanish with the verdict on edit
(no separate `unfinished` signal per component any more — `Cards` and `GroupsEditor` read
`verdictOf`).

## 3. What the screen shows

**On a card / group (left):**
- dot: amber / green / red per §1; `data-state` = `unconfirmed` | `confirmed` | `rejected`.
- below the header, only when `verdictOf(...)?.verdict === "rejected"`: the verdict's findings,
  red, one per control, with the field pointer as now (`issueFindings` placement unchanged).
- live warnings from the probe (`severity: "warning"`), amber, as now.
- the "resolves to …" line from the probe, as now (information, not a finding).
- **removed:** the red banner at the top of the Process tab (`processing.tsx` ~348–370, both
  the loose-issues list and the `errors` prose fallback); the live red issue list per card
  (`schemaIssuesForNode` rendering of error-severity issues); the live group issue list
  (`issuesForGroup(probe.issues, name)` in `GroupsEditor`); `staleFindings` (nothing to dedupe).

**Next to Run pipeline (right):** one line, red, `data-needs-attention`, shown while the last
probe reported anything wrong: "Needs attention: `cluster`, `group_2`" — the distinct items the
probe's error-severity issues point at (on this server that is the same condition as
`valid: false`), nodes by id (index → `cards.nodes[i].id`, or
"card N" if unnamed), groups by name, and "the document" for an issue with no item pointer (a
cycle, a duplicate id). Names only — the messages are on the items after Confirm. Hidden when the
probe is valid or has not answered.

**Run failures:** `results.tsx` keeps handing `issues` to the store, together with the document
that was sent; `reportRunIssues` now also records a **rejected** verdict per pointed item (node
or group), bound to that sent document, with the findings derived as Confirm derives them
(`findings.ts` — the server's own sentence for `empty` and `unproduced`, the refused value for an
enum), so the items go red exactly as if confirmed. The pane's own headline
("N cards and M groups need attention") stays.

## 4. Confirm, restated

- Card: `checkNode` (a name) → `validate-card` → `askProbe`; findings = the union as now;
  `recordVerdict(key, node, findings.length ? "rejected" : "confirmed", findings)`. A probe that
  cannot be asked is a rejection with the "Could not reach DashiBoard" finding (as now).
- Group: `askProbe` → `issuesForGroup`; same recording.
- Warnings are not findings: filtered out before the verdict on every path (the `validate-card`
  path and the probe path for cards; the probe path for groups).

## 5. Tests

- `stores.test.ts`: a verdict is returned only for the same signature; an edit (different
  value) yields `null`; `recordVerdict` twice in one tick keeps both (updaters); persistence under
  `dashi.verdicts`; `forgetAllVerdicts`.
- `processing.test.tsx`: a fresh card's dot is `unconfirmed` (amber class) even while the probe
  reports an error for it, and no `[data-issue-severity="error"]` renders; Confirm on a broken
  card → `rejected` dot + findings; edit the card → `unconfirmed`, findings gone; Confirm on a
  good card → `confirmed`; a live warning renders amber before Confirm and leaves a green dot
  green; the top banner no longer exists (`[data-probe-banner]`, or the destructive box's text,
  absent while the probe reports errors).
- `GroupsEditor.test.tsx`: same four transitions for a group; the empty-group message appears
  only after Confirm.
- `results.test.tsx`: the pointer lists `cluster, group_2` from seeded probe issues, "the document"
  for a pointer-less issue, and is absent when valid; a failed run turns the pointed items
  `rejected` (assert through `verdictOf`).
- Every new assertion mutation-tested; `STRICT_READ_UNTRACKED` stays 0.

## 6. Out of scope

Blocking Run on red items (allowed by decision). Announcing what a deletion cascaded into. The
`_id` column. Saved documents.

## 7. Process

Same branch, one commit per task, review per task, whole-branch review; nothing pushed until the
owner says. Supersedes the "live-error dot" commit's behaviour (`786f8d6`) by decision; the
"could not reach" finding and the proxy route stand.
