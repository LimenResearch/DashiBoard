# Asked, not observed — one source for red, and what an upload asks

Why: the verdicts work (PR #170, 2026-09-17) made every item amber until asked, but left one
place that still paints red on observation: the "Needs attention" line next to Run pipeline reads
the continuous probe, so it names items the moment the server objects, before Confirm or Run.
Behind it sit two more defects with the same root. `reportRunIssues` writes the probe store
outside its sequencing, so a stale probe reply erases a failed run's names from the line (measured
2026-09-17: one issue after the run, none after the reply; the card's verdict survived). And
Confirm never reads `answer.valid`/`answer.errors`, so an item in a document that cannot build
confirms **green** — measured with the server's own reply for two cards named `a`; the same holds
for a loop, and for any document "Upload cards" brings in. Decided with the owner on 2026-09-18:
**red comes from verdicts only; Confirm refuses a document that cannot build; an upload is an act
of asking, never refused.** Baseline: `ds-DashiUI` @ `dfb77cb`. No Julia change.

## 1. One source

The line lists the items whose verdict on their current content is `rejected` — nodes by id (or
"card N" for an unnamed one) in document order, then groups by name in theirs — and nothing else. It appears
when a Confirm, a failed Run or an upload rejected something; an edit expires the verdict and
drops the item; it is absent when nothing is red. It reads `verdictOf` per item, the same call
the dots make, so the two cannot disagree.

`PROBE_STORE` keeps one writer, the continuous probe, sequenced by `probeSeq`. What still reads
it is everything that is live and amber by design: warnings on cards and groups, "resolves to",
the `unproduced` names. `reportRunIssues` stops writing it (§3). The document-fault block under
the Run row (`[data-document-faults]`, added 2026-09-17 as a stopgap while the line read the
probe) is removed: a document fault is now shown where it was asked for (§2, §3, §4).

Lost, and accepted: a broken document shows nothing next to Run until someone asks. Run stays
allowed; Confirm on any item, a failed Run and an upload all ask.

## 2. Confirm refuses a document that cannot build

The rule, for a card's Confirm and a group's alike: the probe answers `valid: false` and **no
error issue points at any item** (`itemKey(pointer) === null` for all of them, or `issues` is
empty) — then `errors` describe the document, and the item being confirmed is rejected with
those sentences as its findings, verbatim.

Not "refuse whenever the document is invalid". If card B has a schema error, confirming card A
still goes green: B's issue is pointed at B, and is B's business. This is sound because the
server reports in layers: schema failures and empty groups come back pointed, before building;
build faults (loop, duplicate id, `pass_through`) come back with `issues: []`; `unproduced` is
computed only after a successful build. An issue whose pointer names no item is treated as a
document fault too — that case does not occur today and the rule should not depend on it.

The existing order of questions stands: `checkNode` first (ours alone), then `validate-card`,
then the probe; a `null` probe (server unreachable) still rejects with "Could not reach
DashiBoard". `graphFindings` gains the document rule; the group handler gains the same three
lines.

## 3. A failed run

Unchanged in what it shows: pointed error issues become `rejected` verdicts on their items, the
server's text goes under the Run button with the pipeline/execution heading. Changed in what it
touches: `reportRunIssues` no longer writes `PROBE_STORE`. It becomes the one function that
turns a server's pointed issues into verdicts on a snapshot, and §4 reuses it. Rename it to say
so (`rejectFromIssues`, or similar); the headline logic around it is not part of this spec.

## 4. An upload asks

`importCards` refuses nothing: a broken document is loaded exactly as it is, so the author can
fix it here. That is the point of the form.

Right after import, the Process tab asks once on the author's behalf, from the imported
snapshot, and records what the server rejects:

1. **Pointed issues** → `rejected` verdicts on their items, through the function of §3. Those
   cards and groups turn red with the message on them; the line names them; fixing one drops
   its verdict. Warnings are not recorded (they stay live and amber). Nothing is *confirmed*:
   an item the probe has nothing against stays amber, because nobody looked at it. Green keeps
   meaning "asked and answered".
2. **Two cards with one name** — the fault the server reports without a pointer, and the rule
   the UI already owns (`setNodeId` refuses it). The UI places it itself: every card after the
   first with a taken name is rejected with `There is already a card called "a".`, and a missing
   id counts as `""` as in `setNodeId`. Rename either card and its verdict expires. This is a UI
   finding, recorded whether or not the probe could be reached.
3. **Any other fault the UI cannot place** (a loop; `pass_through`; an unreachable server) →
   the server's sentences under the Upload button, in the dress of a failed run's text:
   "The uploaded document does not build:" followed by the lines. Cleared by the next upload or
   the next edit of the document. After that, the general rule of §2 keeps the fault reachable:
   Confirm on any item rejects it with the same sentence.

The upload's probe is a separate `askProbe` on the snapshot, not the continuous probe's reply:
the continuous probe writes the store and nothing else, and its reply may be a later document.

## 5. What the screen shows, restated

| event | on the item | next to Run | under a button |
|---|---|---|---|
| edit | amber; verdict gone | item dropped | — |
| Confirm, item fine, document builds | green | — | — |
| Confirm, item at fault | red + findings | named | — |
| Confirm, document does not build | red + the server's sentence | named | — |
| Run fails, pointed | red on each item | named | server's text under Run |
| Run fails, unplaceable | — | — | server's text under Run |
| Upload, pointed | red on each item | named | — |
| Upload, duplicate names | red on the later card(s), UI finding | named | — |
| Upload, unplaceable | — | — | server's text under Upload |
| probe objects, nobody asked | amber; warnings only | — | — |

## 6. Tests

Written first, watched failing, mutation-checked where a test would pass before the change.

`results.test.tsx` — the line:
- absent while the probe objects and nobody asked (replaces the three tests that pin the probe
  as source, `296–375`; rewritten, not extended);
- names an item after `recordVerdict(…, "rejected")`, a card by id, an unnamed card as
  "card N", a group by name; gone after the item's edit; gone after `forgetVerdict`;
- a failed run with a pointed issue: named, and still named after a stale probe reply lands
  (the measured 3b scenario, now a regression test);
- a failed run with `issues: []`: nothing on the line, the text under Run;
- no `[data-document-faults]` element exists.

`processing.test.tsx` — Confirm:
- the server's literal duplicate-id envelope (`valid:false, errors:[…], issues:[]`) → the card
  is rejected with that sentence; the loop envelope likewise;
- another card's pointed schema issue → this card confirms green;
- Upload: an uploaded document with a pointed issue → that card red, the other amber, the line
  names it; with two cards named `a` → the second red with the UI sentence, the first amber;
  with a loop reply → the text under Upload and every dot amber; an edit clears the text.

`GroupsEditor.test.tsx` — the group's Confirm rejects on the duplicate-id envelope; confirms
green when the only issue is pointed at a card.

`stores.test.ts` — the renamed §3 function records rejections and leaves `PROBE_STORE` alone
(mutation: restore the write, the test goes red); the duplicate-name finding: which cards it
marks, `""` counted, none when names are distinct.

## 7. Out of scope

- The run-failure headline "see the marks on them" over-promising when an edit lands mid-flight
  (todo 2b) — one sentence, same function, a separate change.
- `importCards` performs no shape check: a file that is not a cards document goes straight into
  the store. Noticed here, not fixed here.
- A late group Confirm resurrecting a verdict a remove/rename just cleared (todo 2a).
- Marking a `through` chain that names a node that no longer exists (todo 3c); the server-side
  `through` validation (`2026-09-18-through-chain-validation-design.md`).

## 8. Process

UI only, `dashiboard-ui/`; the team leader is working in `Pipelines/` in parallel. TDD per
file; suite, `tsc`, lint and build clean before hand-over; nothing committed by the implementer
— the owner reviews and commits. Owner's browser checks afterwards: upload `dup.json` (two cards
`a`) and see the second card red with the name sentence; upload a looped document and read the
text under Upload; Confirm a card in it and see the loop on the card; make a card's schema fail,
Confirm its neighbour, see green.
