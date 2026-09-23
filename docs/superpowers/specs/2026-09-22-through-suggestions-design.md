# Through suggestions that the server can produce

Why: the text box and the panel offer, after a name, the nodes a chain may pass through. The rule
in place — a node that *reads* the value — is necessary and not sufficient. Measured 2026-09-22
on a throwaway server against the server's own verdict, it offered 6 of 10 one-step chains that
the server then refuses (`.superpowers/sdd/todos/…`, "through smoke test"). Owner, same day: fix
the clear case first, treat the edge cases separately, and stress-test the engine against
producible combinations. Baseline: `ds-DashiUI` @ `b1d96fe` plus the working tree of that day.
`dashiboard-ui/` and `DashiBoard/src` change; `Pipelines/` does not.

## 1. What `through` is, in `Pipelines`

`{cols = "X", through = ["a", "b"]}` is a **name**: `pass_through` (`group_api/deps.jl`) builds
`X_<suffix(a)>_<suffix(b)>` from `node.card.suffix` of each listed node and nothing else. Later,
`unproduced_references` (`pipeline.jl`) asks whether that name is among the columns anything
produced; the probe reports the answer as `unproduced`. So a step is right when, for every name
`N` the chain carries, **`join_names(N, suffix(n))` is among `n`'s outputs**. "Reads it" follows
from that; the converse does not hold.

The decision table, per value kind and step:

| value | carried into step 1 | criterion for step `n` | needed |
|---|---|---|---|
| `cols:X` | `X` | `N_suffix(n)` ∈ outputs(`n`), every carried `N` | `n`'s suffix and outputs |
| `nodes:m` | outputs of `m` | same | outputs of `m` |
| `groups:g` | resolved columns of `g` | same | the server's resolution of `g` |
| step k ≥ 2 | the names produced at step k−1 | same | outputs of the previous step |
| any | — | `n` referable from the item (§6 of the selector spec) | `referable` |
| any | — | `n` not already in the chain | nothing |

A card that adds its suffix to its **targets** — `interp`, `glm`, `streamliner`, and `rescale`
for its `targets` as well as its `inputs` — is a valid step for a column or group that is among
those targets: `TEMP` in `interp.targets` yields `TEMP_hat`, and `{cols = "TEMP", through =
["interp"]}` is produced (measured). Owner, 2026-09-22: such cards must be offered.

Where the criterion fails, measured:

| card | why `through` cannot pass through it |
|---|---|
| `cluster`, `split`, `window_function`, `dimensionality_reduction` | no `suffix` field: they name their outputs themselves (`cluster`, `partition`, `component_1…`); `pass_through` throws `FieldError`, surfaced as a pointer-less build failure |
| `gaussian_encoding` | has a suffix but produces `X_gaussian_1…n`; `X_gaussian` is unproduced |
| `interp`'s `input`, `glm`'s formula inputs | read but not transformed: only the targets get the suffix, so the card is a valid step for its targets and not for these |
| `wild` with `suffix = nothing` | names `X_nothing` |
| a rescale with `invert = true` | the probe does not honour `invert` today (reports it as forward) |

## 2. Stage 1 — never offer a node that names its own outputs

**Rule:** a node is offered as a through step only if its card type has a `suffix` property, and
reads the carried name, and is not already in the chain, and is referable. The card IR the UI
already holds (`payload.cards[type].properties`) says which types have `suffix`; the document
says each node's type. No server change, no new request.

- `throughOptions(row, all, nodes, groups, suffixed)` gains a fifth argument, the set of node ids
  whose card type carries `suffix`, computed once per IR reply in `processing.tsx` /
  `GroupsEditor.tsx` (`suffixedNodes`). A node absent from it is never offered.
- The rule applies to the text box's suggestions and to the panel's chain builder alike, since
  both go through `chainFor`.
- A target-suffixing card is offered for a value among its targets, as §1 requires: it has a
  suffix and it reads the value. Stage 1 cannot yet tell a target from a mere input (`interp`'s
  `input`), which is §4's business.
- Measured effect on the smoke document of §1: the four suffix-less cards stop being offered;
  `interp` stays offered for `TEMP` (its target) and, until Stage 2, also for `id` (its `input`);
  `gaussian_encoding` stays offered until Stage 2.

Tests: `through.test.ts` — a node whose type has no suffix is not offered although it reads the
value; one with a suffix still is; the smoke document of §1 as a fixture, asserting the four.
`processing.test.tsx` — a `cluster` card reading `TEMP` is not offered after `cols: TEMP`.

## 3. Stage 2 — the server describes derivations; the engine becomes lookups

Approved in outline 2026-09-22 (a: `extends` and `groups` in the reply; b: `without` on the
probe; c: scratch-card ground truth). Written here so Stage 1 does not close the door on it;
planned separately.

- **Reply.** Each `nodes[i]` gains `extends: {input → [outputs]}`: for each input `x`, the outputs
  that extend it by the node's suffix rule — one name for `rescale`, `interp`, `glm`,
  `streamliner`, `wild`; several for `gaussian_encoding` once `pass_through` can name them
  (a `Pipelines` change, the leader's — until then its list is empty and it is not offered);
  empty for suffix-less and inverted cards. The reply also gains `groups: {name → resolved
  columns}`, from `pipeline.enriched_digraph.groups`, which is computed today and not reported.
  Both are built in `handlers.jl` from the built pipeline, next to a comment naming this the one
  place the naming rule is echoed.
- **Engine.** Carried names: `[X]`, `outputs(m)`, `groups[g]`. A step `n` is offered iff every
  carried name is a key of `extends(n)`; the values are carried forward. Nothing is concatenated
  in the browser (A10). The `suffixed` set of Stage 1 becomes redundant and goes.
- **Half-built documents.** The probe request takes `without: {nodes: [i]} | {groups: [name]}`;
  the server drops those items and everything depending on them, builds the rest, answers in the
  same shape. A field asks for the document minus its own item when a chain stage starts, cached
  by document signature; it reads `nodes` and `groups` from that answer and ignores `referable`.
  The memory of the last successful probe (`describedNodes`) goes.
- **Stress test, offered ⇔ producible.** `DashiBoard/test`: example documents (one per card type,
  chains of length 1–3, a group, a suffix-less card, `wild` with and without suffix). For every
  `(value, chain)` position and candidate node, the lookup on the reply is compared with the
  ground truth *add a scratch card reading that reference and build*: produced and no throw ⇔
  offered. The run writes `dashiboard-ui/src/fixtures/through-cases.json` (reply plus expected
  sets), which a UI test drives `throughOptions` over.

## 4. Edge cases, each its own decision

| case | today | treatment |
|---|---|---|
| `gaussian_encoding` | offered, unproduced | not offered from Stage 2 until `pass_through` names fan-out outputs (`Pipelines`, reported to the leader); the owner wants it valid eventually |
| `interp` on its `input`, `glm` on formula inputs | offered, unproduced | Stage 2's `extends` maps only the targets, so the card is offered for a value among its targets and not for one it merely reads |
| `wild` with `suffix = nothing` | names `X_nothing` | Stage 2: empty `extends`; reported to the leader as a `Pipelines` default bug (`join_names(targets, suffix)` is not broadcast) |
| inverted `rescale` | the probe ignores `invert` | reported to the leader; the engine follows whatever the probe reports |
| suffix-less card in a `through` | raw `FieldError`, no pointer | reported to the leader: a pointed issue would let the UI place it |

## 5. Process

Stage 1 is a bounded change on the working tree, tests first, one commit. Stage 2 gets its own
plan from this spec once Stage 1 is in the owner's hands. Browser check for Stage 1: after
`cols: TEMP` in a document holding a `cluster` and a `rescale` that both read `TEMP`, only
`rescale` is offered; in the panel's chain builder likewise.
