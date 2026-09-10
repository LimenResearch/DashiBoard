# 06 — Implementation plan

Derived from `01-decisions.md` and the three reconnaissance briefs. Ordered by what blocks what.

**Organising principle: the card-derivation refactor is standalone.** Every correction the briefs
made landed in the integration layer. Track A below is the actual refactor and depends on no other
repository. Start there; the cross-repo work sequences around it rather than gating it.

**What the two-artefact decision (§13) removed from this plan.** The server emits an ordered IR for
rendering beside the JSON Schema for validation. That retired four items which were only ever there
to make one document serve both purposes:

- **`x-dashi-order`** — order is structural in the IR, so nothing annotates it onto a schema.
- **Variants into `$defs` + `$ref`** — that was to give a renderer variant identity; the IR's keyed
  variants supply it, and the schema keeps its inlined `allOf`.
- **`oneOf` + discriminator** — measured to give markedly worse errors than the gated `if`/`then`
  the code already emits. Nothing needs the schema contorted for a renderer any more.
- **"Merge, never replace"** — AgentGraph's rule, about *their* mechanism of overwriting a finished
  property with a `$ref`. Ours never did that: `schema_definitions` constructs the vocabulary fresh
  and `card_schema` assigns a whole new `$defs`. Adopting the rule would have introduced the hazard
  it was written to prevent (A3e).

**A pending decision, and it gates integration but not verification.** ExperimentTracking pins
Pipelines to the GitHub URL, not `../Pipelines`, resolving to `~/.julia/packages/Pipelines/ruNcy`.
Until that is a dev path, a Pipelines edit is invisible to ExperimentTracking's own environment,
tests and CI until it is pushed. It is a real change to another repository's `Project.toml` and is
the project owner's decision, not one for the sessions to settle between themselves.

It does **not** block checking work as it lands. A throwaway environment whose `[sources]` dev-pin
the working trees resolves in about fifteen seconds and modifies neither repository. Use that to
verify against shipping code while the decision is pending.

**What was verified against the working tree, not merely the resolved package.** The schema
machinery — `structs/json_schema.jl`, `structs/card_schema.jl`, `group_api/schema.jl`,
`structs/style.jl`, `widgets.jl` — is byte-identical between the two, so every schema-shape finding
describes shipping code. `group_api/deps.jl` and `dag.jl` differ, so the behavioural results were
re-run: the column-validation table reproduces row for row, A4's `graphviz` `MethodError` on a
`GroupDiGraph` still throws, and B2's dialect mismatch still rejects the repo's own example card
under the served schema while the validated one accepts it. The reason it reproduces is structural:
`validate_pipeline_schema` is the first statement of `Pipeline(nodes, groups, cols)` in both trees,
so the schema verdict is reached before any divergent code runs.

---

## Track A — DashiBoard only. Blocked by nothing.

| # | Work | Notes |
|---|---|---|
| A1a | **Fix the tag-equality gate in `style.jl`** | A1 breaks the parser without it. Mandatory first commit. |
| A1 | Add `title` and `description` to the `dashi` tags on every card and method struct | The labels and help text that today live in `assets/config/*.toml`. Not mechanical — see A1a. |
| A2 | Delete `assets/config/*.toml`, every `CardWidget` method, `card_widgets()`, and `widgets.jl` | Nothing else may reference `Widget` or `OutputSpec` afterwards. |
| A3 | **Emit the IR beside the validation schema, from one traversal** | The keystone. §13. The renderer builds from the IR; the schema validates. **Half landed, 2026-09-09.** The IR itself is on `main` in the new `DashiBase` package (`3e7c2e5`, `cd2e88b`, `66bdff2`), and `card_schema` already builds through it — but it is discarded: `Pipelines/src/card_schema.jl:33-34` holds `ir` as a local and returns only `json_schema(ir)`, and no route serves it. **What remains is one small change:** add `Pipelines.card_ir(key, variable_config)` returning the IR, declare it and the imported IR types `public`, and reduce `card_schema` to `json_schema(card_ir(...))`. Today `DashiBase` declares no `export` and no `public` at all, and `Pipelines.jl:43-45` imports the IR types without publishing them, so ExperimentTracking cannot serve the IR without reaching through two packages' internals; that session will add the wire method once the names are public. Two IR defects found by execution and still open: `IR_DICT` maps `"boolean" => IntegerIR` (`DashiBase/src/IR.jl:172`) so `{"type":"boolean"}` deserialises to `NumericIR{Int64}`, live via `StreamlinerCore/src/schema.jl:7`; and `NumericIR`'s four bound fields are typed `Maybe{Int}` while `default`/`enum` use `T`, so `NumberIR(minimum = 0.5)` throws `InexactError`. Neither is reachable from any TOML today. |
| A3a | ~~Stop emitting `type`/`default` siblings beside a `$ref`~~ — **RESOLVED 2026-09-09 by the IR rewrite.** What remains is only **pin `$schema` / emit a `dialect` key** | The sibling half is gone: `schema_from_type` no longer exists, and `merge_IR` discards the inferred IR when the tag is a `ReferenceIR` (`DashiBase/src/auto_IR.jl:7`), so `$ref` emits alone — verified on a required and a defaulted field. **This removes A3a as a blocker on B2's path.** Nothing emits `$schema` or `dialect` anywhere, so that half is untouched and unblocked by anything. See detail below. |
| A3b | Add a `MethodSpec` so method variants have labels | The IR's variant entries have no title source today. |
| A3e | Copy the `$ref` constants rather than sharing them | Hygiene, not a blocker — see below. Pairs naturally with A1a. |
| A4 | Make `graphviz` work for `GroupDiGraph` | Currently a `MethodError` on group-API pipelines, so §5's canvas has nothing to render. |
| A5 | Design out the positional `weights` rule | §12. Mark `inputs` unordered, or make the correspondence explicit. |
| A6 | Filter schema derivation *and* filter IR | The 1–2 day item §8 did not originally budget. |
| A7 | Give `SchemaValidationError` a JSON Pointer and a `related` array | Mostly plumbing — see below. |
| A8 | Validate the **node wrapper**, not only `node["card"]` | A typo like `trian = false` is accepted and silently ignored today. |
| A9 | Fail closed when the variable context is missing | `VariableConfig`'s `nothing` means *unconstrained*, so omitting `cols` validates everything. |

### A3 in detail — the rules that are easy to get wrong

- **Construct, never annotate.** Build each schema and IR node complete, rather than assembling
  something and writing into it afterwards. This is how the code already specialises vocabularies,
  it is what makes A3e a tidy-up rather than a blocker, and it removes a whole class of aliasing
  and ordering bugs by construction.
- **Make nullables actually nullable.** `type: ["string","null"]` with any enum at the same level.
  Two payoffs: violations report `enum` and name the options rather than *"not valid under any of
  the given schemas"*, and it fixes a live disagreement where the schema forbids null while
  `StructUtils.lower` writes it.
- **`additionalProperties: false` at every authored level**, not only on leaf objects — and the IR
  must carry the equivalent, since strictness has to reach both consumers.
- **Do not migrate the union to `oneOf`.** Keep the enum gate plus `allOf` of `{if, then}` that
  `tagged_schema` already emits. Measured, `oneOf` reports errors from every variant while the gated
  `if`/`then` reports only from the branch the discriminator selected. §13 has the table.
- **`groups` is a distinct IR entry kind**, so the renderer dispatches to the purpose-built variable
  picker rather than inferring a widget from an object with `additionalProperties`. This is type
  identity, not a widget override, and does not breach §4.
- **The IR's addressing must line up with the schema's JSON Pointers.** Otherwise a validation error
  cannot be attached to the widget the IR built. This is the seam most likely to be got wrong, and
  it is worth a test that feeds a deliberately invalid card through both and asserts the error lands
  on the right entry.

### A1a in detail — adding a label breaks the parser

`style.jl:14` gates the vector-to-string lift on `get_dashi(tags) != JSON_VARIABLE` — an equality
comparison against one exact dict, `{"$ref": "#/$defs/variable"}`. That lift is the normal path by
which a group-API selector reaches a singular variable field: a config authoring
`partition = {nodes = ["partition"]}` resolves through `Context` to a one-element vector, which the
lift turns into the `String` the field declares.

**Twelve fields are tagged exactly `dashi = JSON_VARIABLE`** — `glm.jl:197,198,236,237`,
`rescale.jl:114`, `interp.jl:92,94`, `streamliner.jl:118`, `gaussian_encoding.jl:89`,
`dimensionality_reduction.jl:49`, `cluster.jl:111,112`. Adding a `title` to any of them makes the
tag a two-key dict, the equality fails, and every config using a selector for that field stops
parsing — including `ExperimentTracking:test/static/configs/config.toml:36`. It fails loudly and the
suites catch it, so this is confusion rather than silent corruption, but it is confusion on the
critical path with a misleading message: the error interpolates `JSON_VARIABLE` and tells the author
their schema must equal it, while their schema *is* it plus a label.

**Fix, one line:** compare on the `$ref` rather than the whole dict —
`get(get_dashi(tags), "$ref", nothing) == JSON_VARIABLE["$ref"]`. That makes the gate depend on the
field's type identity, which is what it was always expressing. There are no siblings of the pattern:
`get_dashi` has two call sites, this gate and `composite_schema`'s merge, which is indifferent to
extra keys; `JSON_VARIABLES` and `JSON_NONEMPTY_VARIABLES` are only ever used as values, never
compared.

### A3a in detail — resolved by the IR rewrite; only the dialect pin remains

`schema_from_type` merges the `dashi` tag into the derived schema, so `input::String &
(dashi = JSON_VARIABLE,)` emits `{"type": "string", "$ref": "#/$defs/variable"}`. Under a validator
that discards `$ref` siblings — JSONSchema.jl does — the `type` is dropped and it works. Under one
that applies them, and **every modern JS validator applies them regardless of declared draft**, both
constraints hold at once.

Two symptoms, one cause. A singular variable field becomes **unsatisfiable**: string ∩ (object|array)
is empty. A list-valued field is merely **narrowed**: `inputs` emits `type: "array"`, the target
permits object or array, so the intersection is array-only — which silently rejects the single-item
form `inputs = {cols = ["No"]}` while accepting the list form, in the same file. Both appear in
`Pipelines/test/static/configs/groups.toml`.

Pin `$schema` for determinism, but the fix is dropping the siblings; pinning alone preserves the
accident.

**Status, verified 2026-09-09.** The sibling half is **resolved**, and not by anyone planning it — the
team leader's IR rewrite removed it as a side effect. `schema_from_type`, the function this entire
finding named as the cause, no longer exists anywhere in the tree. In its place `merge_IR` short-circuits
on a `ReferenceIR` tag — `return if i1 isa TrivialIR || i2 isa ReferenceIR; i2` — discarding the
type-derived IR entirely (`DashiBase/src/auto_IR.jl:7`), so only the `$ref` survives into the schema.
Probed against a struct carrying `VARIABLE_DEF` on a required `String` and `VARIABLES_DEF` on a
`Vector{String}` with a `String[]` default, i.e. both symptoms above: each property came out
single-keyed, `{"$ref": …}`, with no `type` and no `default`. The unsatisfiable-singular and
narrowed-list symptoms are therefore both gone, and the two forms in
`Pipelines/test/static/configs/groups.toml` — `{cols = "No"}` and `{cols = ["No"]}` — are now the
`OneOrManyIR` case rather than a validator accident.

The measurement above is kept deliberately. It is the reason not to reintroduce a merged sibling when
someone next wants to attach a `title` beside a `$ref`, and A3b will create exactly that temptation.

**What remains of A3a is the other half:** nothing in Pipelines, DashiBase or DashiBoard emits a
`$schema` or a `dialect` key. So §13's `dialect: "dashi/1"` and the client's refusal of unknown majors
are unimplemented. That work is small, gated by nothing, and no longer shares a commit with the sibling
fix — so A3a should be re-read as a one-line addition rather than as a blocker.

### A3e in detail — hygiene, and why it is no longer a blocker

At `$defs` depth the emitted schemas share object identity with module constants: in the group
dialect, 24 paths alias three of them — `JSON_NODE` at 12, `JSON_GROUP` at 6, `JSON_COL` at 6, all
at `.../properties/{nodes,groups,cols,through}/items`.

That count is established twice over — measured by walking a built schema, and derived from the
source: `variable_item_schema` embeds `JSON_NODE` twice (`nodes` and `through`) and the other two
once each (`group_api/schema.jl:14-19`); `one_or_many_schema` embeds its argument at two paths, as
the object branch's `then` and as the array branch's `items` (`structs/json_schema.jl:190-199`); and
`schema_definitions` calls it once on the singular item schema and twice on the plural (`:33-38`),
giving six reachable item schemas × (2, 1, 1).

`const` protects the binding, not the
contents, so writing through any of those paths mutates the constant process-globally and
permanently. Measured: an annotation written through one card's schema appears in a freshly built
schema for a different pipeline.

**Under the two-artefact design nothing writes into a served schema, so this cannot fire.** It was
a blocker only while the plan carried `x-dashi-order` and "merge into the existing property dict",
both of which the IR removed.

It stays on the list because the sharing is invisible — nothing in `json_array(; items = JSON_NODE)`
signals that the result holds a reference into a module global — and the next person to reach for a
quick annotation gets a silent cross-request leak with no error leading back. `copy()` at the six
use sites (`group_api/schema.jl:15-18`, `structs/card_schema.jl:29-30`), or make the constants
zero-argument functions. Near-zero cost, and it composes with A1a: once the gate compares `$ref`
rather than whole-dict equality, nothing depends on those constants being singletons.

### A3b in detail — variants have no labels

Cards carry `CardSpec.label`, so a card variant can be titled. **Methods cannot.** They register as
`OrderedDict{String, Type}` — a key and a bare type, with no label anywhere — across seven
`*_METHODS` dictionaries, plus the four places that index them. A1 adds `title` to the *fields* of
`KMeansMethod`; it does not give the variant `"kmeans"` a display name, and every type-selector
below the card level needs one.

Two constraints on the replacement. The registries **overlap by construction** —
`DISSIMILARITY_METHODS` is built by `merge` from `METRIC_METHODS` plus two extras — and round-trip
correctness depends on shared entries agreeing on their keys. Flatten them into two independently
written tables and the save path can emit a name the load path rejects, silently and only for the
shared entries. Second, the emitted schema currently holds a **live `keys()` view** into each
registry, so a `MethodSpec` table should be immutable or copied at emission.

### A7 in detail — smaller than it looks

`JSONSchema.SingleIssue` already carries everything the error contract needs except one field. Its
`path` is `"[method][type]"`, mechanically convertible to a JSON Pointer; its `reason` is the failing
keyword; and on an enum failure its `val` **is the list of valid options** — what a form needs to
render a correction rather than a complaint. `SchemaValidationError` keeps only a prose culprit and
the raw issue, so A7 is largely plumbing `SingleIssue` through. The `related` array is the only part
with no existing source.

**Surface leaf errors, never composition summaries.** A validator may report the real failure *and*
a summary from whichever combinator wrapped it. The summary is the useless line; the leaf beneath it
carries the reason as **data** — Ajv's `params.allowedValues`, Python's `leaf.validator_value`. Keep
the deepest leaf per path and pass those params through rather than flattening to a string.

**Do not copy an offender list from another stack.** Which combinators summarise is
validator-specific, and measured, the three disagree:

| | `allOf` | `if`/`then` | `anyOf` | `oneOf` |
|---|---|---|---|---|
| Ajv 8 (browser) | — | leaks | leaks | — |
| Python `jsonschema` | — | never surfaces | leaks | — |
| **JSONSchema.jl (server)** | **propagates** | **propagates** | leaks | leaks |

`allOf` returns the inner result unchanged and `_if_then_else` returns `_validate(x, then, path)`;
neither constructs a `SingleIssue`. So **our union shape leaks nothing** — a bad value three levels
down arrives as `path="[method][dissimilarity][p]", reason=minimum`.

**Occurrence counts matter as much as behaviour.** Across all nine cards, `anyOf` appears **zero**
times — so AgentGraph's offender list is inapplicable here, not because our validator differs but
because we never emit the keyword. `oneOf` appears **six times per card**, every one from
`variable_item_schema`'s `oneOf: [required nodes | required groups | required cols]`
(`group_api/schema.jl:20-25`) — section 6's picker.

**And that one leak is a UI problem, not an error-plumbing problem.** The picker's `oneOf`
summarises only when the *selector-kind choice* is malformed — two selectors at once, or none. A bad
value inside a well-formed selector still returns a leaf carrying the allowed columns. Selector-kind
is precisely the error a purpose-built picker makes **unrepresentable by construction**: one radio
group, not three optional fields. So section 6's design retires the only summary we emit — which
makes it a *requirement* on the picker, not a happy accident of it.

**Two traps in `SingleIssue`.** `val` on a variant-name enum failure is a
`Base.KeySet{String, OrderedDict{String, Type}}`, a lazy view over the live registry rather than a
`Vector` — `collect(String, val)` at the boundary. And a `required` failure reports at the **parent**
path with the missing name in `val`, so the pointer alone does not identify the control; the form
must join the two. That is where `related` earns its keep beyond the `weights`/`inputs` pair.

**Path stability is confirmed to three levels.** `"[method][dissimilarity][p]"` is the deepest case
in the card set and converts mechanically to `/method/dissimilarity/p`.

### A8 and A9 in detail — two gaps found by answering AgentGraph's question

Both surfaced while writing a comparison of the two schema layers, which is a reminder that the
cheapest review is someone asking you to state plainly what you do better.

**A8 — the node wrapper is never validated.** `validate_pipeline_schema`
(`group_api/schema.jl:71-99`) validates `node["card"]` and each group. It never validates the object
around the card. `Node(d)` (`node.jl:60-74`) reads `d["card"]` and `get`s `label`, `train` and
`state`, ignoring everything else. So `[[nodes]] id = "x", trian = false` — a typo for `train` —
passes validation, is silently dropped, and the node trains anyway.

This is precisely the defect AgentGraph documented as their own, where six shipped configs had been
ignoring a node-level setting for months through a schema layer whose purpose was to prevent it.
Strictness is the default one level down (`composite_schema`'s `additionalProperties = false` reaches
every nested variant); it is absent at the top. Give the node wrapper a schema.

**A9 — a missing context validates everything.** `VariableConfig`'s fields treat `nothing` as
*unconstrained* rather than empty (`group_api/schema.jl:3-7`), so a caller that omits `cols` receives
a schema with no column enum at all, every column reference passes, and the failure surfaces later as
a SQL error.

AgentGraph's split is the right one and worth copying: **fail-soft enums, fail-closed gate.** An
empty enum should not constrain, but a context that could not be built at all should refuse the
operation rather than validate permissively. Today we have the soft half and none of the hard half.

### A6 in detail — the open call

Filters need what cards already have, built once: a spec registry, StructUtils annotations, a
tagged-union schema over `FILTER_TYPES`, and a hand-written sub-schema for the interval's
`{min,max}` shape — plus an IR, on the same traversal. **Decide first where the annotations live** —
DataIngestion gains a StructUtils dependency, or Pipelines gains a `FILTER_SPECS` table. The bounds
themselves are free: `DataIngestion.summarize` already returns `{min,max}` and unique-sorted values.

---

## Track B — ExperimentTracking. Its own ordering; roughly a week.

| # | Work | Cost | Blocks |
|---|---|---|---|
| B1 | CORS as configured middleware, plus an `assets` parameter on `get_router` | half day | **all frontend work** |
| B2 | `schema_handler` → group dialect; also serve `group_schema` and the IR | half day | Track C |
| | *B2 note:* `run_id` wrapping lives **inside** the `ExecuteThunk` the validation phase returns, not around it — so `probe_result` still dispatches on an `ExecuteThunk`, the probe keeps returning the analysis for `run_id`-bearing requests, and never emits, because emission is in the thunk the probe discards. Asserted in `test/events.jl`. | | |
| ~~B3~~ | **DONE** — `ds-DashiUI` at `b2f38c7`. Probe returns `{valid, source_vars, output_vars}`; `run_id` progress events ported; unknown parameters refused | — | ordering constraint released |
| B4 | Fix the `else` branch in `_execute` | 1 line | — |
| B5 | Filter wire method, once A6 lands | small | filter UI |
| B6 | Registry wire methods for run history | ~40 lines | §9 capabilities |
| B7 | The five orphaned capabilities | 2–3 days | retiring the DashiBoard server |

B1–B4 are small, independent and unambiguously correct — three are bug fixes. They can start now,
in parallel with Track A.

**B3 is one change with two entry points.** The probe returning `{source_vars, output_vars}` and a
document-level method taking `{nodes, groups, filters, cols}` and returning
`{valid, source_vars, output_vars}` are the same work: the method constructs no `DataFlow` and calls
the same `initialize_filters` and `initialize_pipeline`, making it a second caller of one validator
rather than a second validator. Until it exists, an authoring UI validates by sending `""` for
`id_var`, `source` and `destination` — which works today and writes nothing.

Two small fixes belong in the same commit: a missing required field currently reports *"TypeError:
in typeassert, expected String, got a value of type Nothing"* without naming the field, and nothing
checks path validity, which belongs on the request probe and never on the document method.

**B1 is the one real gate.** There is no CORS handling in ExperimentTracking at all: no
`Access-Control-Allow-Origin`, no `OPTIONS` route. Any frontend served from a dev server on another
port fails its first preflighted request.

---

## Track C — the new frontend. Framework free; SolidJS stays.

nexus-weaver-pro recommends the iframe and confirms it removes the constraint that would have forced
React. Rebuilding the frontend *and* migrating framework in one change would multiply risk for no
gain this host can name.

| # | Work | Depends on |
|---|---|---|
| C1 | Recursive renderer over the **IR** | A3 |
| C2 | The variable picker — selector kind, `through`, union repeater — reused for card fields and "Add group". Selector-kind must be unrepresentably wrong (A7) | A3, B2 |
| C3 | Canvas: auto-laid-out DAG, side editing panel, no stored positions | A4 |
| C4 | Connect source, results panes | B7 |
| C5 | `/embed` route and the `postMessage` contract. **Scope corrected and theming settled, 2026-09-09** — see *C5 in detail* below. The contract is far thinner than this row originally implied. | Track D |
| C6 | Runtime API base address, never a build-time constant | — |
| C7 | Validate with the schema; attach errors to IR entries by pointer | A3, A7 |

---

### C5 in detail — the embed and theming contract

**There was no contract to implement against.** nexus-weaver-pro has never embedded DashiBoard: its
`/dashiboard` page is self-contained demo scaffolding, its `listPipelines`/`runPipeline`/
`linkPipelineToNode` client methods hit routes its backend does not serve, and it reports no
`iframe`/`postMessage`/`/embed` usage anywhere in `src/`. So C5 is designed, not discovered.

**The data boundary is thin.** The only DashiBoard relationship that repository models is
`RichNode.dashiboardPipelineId` — one node pointing at one whole pipeline. So the contract is a
pipeline id in, and a pipeline-id selection back out to `linkPipelineToNode`. Nothing richer is
warranted, and building for a richer one would be speculative.

**Theming crosses the boundary explicitly**, because CSS custom properties do not inherit across a
frame — the host's own `hsl(var(--…))` bridge (`nexus-weaver-pro:src/lib/agGridTheme.ts`) works only
same-document. Settled 2026-09-09 with that session, owner-directed:

- **Scope is per-deployment branding with light/dark on top.** Both token *values* and a *mode* cross.
- **Mode travels in the frame URL** (`?theme=dark`), read **once at load and never again**. This is
  what lets the frame get the mode before first paint, so a light panel never flashes inside a dark
  app. The host must **not** re-navigate the frame on a toggle — that would remount the app and
  destroy its state, a worse bug than the flash being avoided.
- **Token values, and every subsequent mode change, arrive by `postMessage`** after a ready signal
  from the frame. Values are bare `H S% L%` triplets in the host's own `index.css` authoring form,
  written straight onto the frame's `:root` with no parsing.
- **The publisher must read *computed* styles, not stylesheet source.** This constrains the host's
  implementation rather than the wire format, and it is easy to get wrong silently. Six of the
  host's tokens are not bare triplets in source: `--radius` is a length, `--gradient-primary` a
  gradient, two are shadows, and as of 2026-09-09 `--ring` and `--sidebar-ring` were refactored to
  `var(--primary)` / `var(--sidebar-primary)`. `getComputedStyle(...).getPropertyValue(...)`
  substitutes `var()` and yields the triplet we agreed; parsing the stylesheet text instead yields
  the literal string `var(--primary)`, which the frame would write onto its own `:root` where it
  resolves against the *frame's* `--primary` or nothing — a wrong or invalid colour, with no error.
  Reported by that session against its own change.
- **The payload always carries the full token set, never a delta.** Same cause, different symptom.
  `--ring` derives from `--primary`, and `--gradient-primary` from `--primary` and `--primary-glow`,
  so editing `--primary` alone silently changes three computed values while only *one* declaration
  differs. A host sending "what moved" — computed by diffing its own declarations — would omit the
  derived tokens, leaving the frame's focus ring drifting out of step with its buttons. Sending all
  38 tokens every time is a few hundred bytes.

**Why both rules need writing down rather than leaving to implementation.** They share a property:
each fails *invisibly against any token that is still a literal.* A smoke test across the palette
passes — only `--ring` and `--sidebar-ring` break under source-parsing, and only derived tokens
desynchronise under delta-sending. Neither bug announces itself; you get one wrong colour, in one
state, after one particular sequence of actions. The derivation itself was the right call — single
sourcing the brand is what makes per-deployment branding tractable at all — but it turned token
collection from an obvious operation into one whose correct and incorrect implementations look
identical until a derived token is read.
- **The payload replaces defaults; it does not supply them.** §9 layer 1 requires DashiBoard to run
  standalone, so the frame ships its own complete palette and a missing or malformed payload is a
  degradation rather than a failure. The host therefore builds no retries and no delivery guarantees.
- **Accent values may repaint once.** Mode is correct before first paint; token values arrive a round
  trip later. That was accepted deliberately — it decouples the frame's first render from the host's
  liveness, and wrong accents for one frame is a detail where a ground inversion would not be.

**Two facts about the host's dark palette that the frame must respect.** As of 2026-09-09 its `.dark`
block defines every custom token (previously it covered stock shadcn only); the sole remaining
asymmetry is `--radius`, which correctly needs no variant. Status hues are lifted ~8–10% in lightness,
and **their foregrounds flip from white to the page ground** — so the light-mode convention of
white-on-everything must not be mirrored, or lifted warning yellow becomes unreadable. Shadows switch
from tinted to pure black at higher alpha, tinted shadows being invisible on a dark ground.

**Exercisable end to end as of 2026-09-09.** The host has a `ThemeProvider`, a complete two-mode
palette, and now a sun/moon toggle merged to its `main` — it matches the OS silently at launch and
never shows a "system" state, the owner having judged a monitor icon to be a state label rather than
an affordance. So the mode a frame receives is something a user can actually change at runtime, and
the mode-change message path has a real trigger to test against rather than a synthetic one. Every
colour value on the host side is settled; 38 tokens before the colour work and 38 after.

**Token values themselves are settled** on the host side as of 2026-09-09 — every colour decision
there is closed, including `--primary`, and nothing is pending that could change a value the frame
consumes. Because the frame reads values at runtime rather than mirroring them, later contrast fixes
propagate with no coordination; one has already happened this way.

**One decision still open, and it is shared rather than the host's alone:** where per-deployment
palette values come from — build-time env, a config endpoint, a swapped CSS file. Until it is settled
no non-default palette can be published at all. **§11 already answers it for DashiBoard by principle**
— prefer the option changeable later without re-authoring the UI, exactly as for the API base — so
DashiBoard's standalone mode needs a runtime source regardless. The open part is whether the host
adopts the same rule, and it should be decided once for both rather than twice.

---

## Track D — nexus-weaver-pro and AgentGraph. Parallel, not gating.

nexus-weaver-pro has six blocking items of its own, of which two matter beyond its own walls:
**registering a new version under an existing alias is unreachable from its UI by any route** — the
one operation an iterative authoring tool cannot do without — and **its Vite dev server occupies
port 8080**, the default of both Julia servers.

AgentGraph needs exactly one change for the save-annotation story: **a route that writes
`content_metadata` on an artifact.** Today that is done by a tool inside the worker process and a
browser cannot reach it.

Four live AgentGraph defects, independent of this refactor, in severity order. **(1) and (4) were
fixed on 2026-09-03** in the `ds-artifact-event` checkout — verified: `load_options` is gone,
`source_options` is a field at `remote_procedure.py:265`, and `validate_remote` now POSTs
`api/v1/probe` carrying the real method name. **(2) and (3) remain open**, and (3) was verified still
open: `source_metadata` appears nowhere in `src/agentgraph/`.

**Those fixes are uncommitted**, on a branch several AgentGraph sessions share as one physical
checkout, under a commit hold requested by another session. So the working stack currently depends
on an unversioned working tree.


1. **A missing capability is reported as a content verdict.** The client posts a `validate` method
   ExperimentTracking `main` does not serve; the resulting error is caught and converted into a
   finding, so a drafting agent receives `{"valid": false, "errors": "...Method validate not
   found"}`. An agent told its correct pipeline is invalid will rewrite it forever.
2. **Error classification keys on response shape, not error code.** Confirmed open, and sharper
   than first described. There are exactly two classes — `RemoteUnreachableError` for transport
   failure or a non-JSON body, `RemoteProcedureError` for anything the server answered — and
   **nothing branches on the JSONRPC code**: it is interpolated into a message string and never read
   again. At `spec.py:616-618` unreachable is re-raised and every other server answer becomes
   `{"valid": False, "errors": …}`. So `-32603` (the server blew up internally) and `-32600` (a
   malformed envelope, i.e. *AgentGraph's own* bug) both reach an iterating agent as "your payload is
   invalid" — and that agent's only available response is to mangle a payload that was already
   correct. Fixing it means classifying on `err["code"]`.
3. **AgentGraph cannot send `cols` at all**, so server-side validation has never run. Its `DataFlow`
   declares six fields with `extra="forbid"` and no `source_metadata`, which appears nowhere in the
   codebase. Confirmed against the server side too: `ExperimentTracking:src/entries.jl:132` reads
   `cols = get(flow.source_metadata, "cols", nothing)` and treats absent as unconstrained, and their
   `test/rpc.jl:134-149` pins both directions.

   **The "~6 lines" scope was wrong** — inherited from the reconnaissance brief and repeated here
   without checking. `extra="forbid"` means `_partition_leaves` would expose `source_metadata` as an
   agent-facing tool parameter unless explicitly excluded, and both `_build_operation_tool` and
   `_build_validate_tool` must populate it. It is also a **behaviour change on every dashi call**
   rather than a migration fix: pipelines that pass validation today would start being rejected —
   correctly, but visibly, and possibly mid-run for someone. Deliberately deferred by the AgentGraph
   session pending its owner's decision, which is the right call.

   The omission is now recorded in their code rather than only in this document: their wire-key guard
   is bidirectional, so `ACCEPTED_WIRE_PARAMS` minus what they send must equal an explicit
   `UNSENT_WIRE_PARAMS` map, each key carrying its reason. `source_metadata`'s entry states the defect
   with its citation and marks it OPEN, so adding the field will fail the test until someone updates
   the map.
4. **`load_options` is silently dropped** — renamed to `source_options` and moved inside `DataFlow`,
   so `nullstr` or `delim` are ignored and the table is mis-parsed. Bounded blast radius.

**The systemic finding, which matters more than any single defect.** Three mechanisms were each
meant to catch a card referencing a nonexistent column, and all three are simultaneously broken or
absent: server-side validation against `cols` never happens (3); the `required_columns` preflight
never fires (1); and the local preflight covers only single-item `{cols = [...]}` selectors,
skipping lists and `nodes`/`groups`. **Card-internal column references are unchecked end to end.**

For DashiBoard that converts a nicety into a requirement: §2's "always send `cols`" is currently the
only mechanism that would work at all. **Nothing in this plan may assume an existing validation
safety net.**

**Partially resolved as of 2026-09-03.** With defect (1) fixed, `dashiboard_validate` now probes
successfully, so the rung that writes `required_columns` can function for the first time. The other
two remain: server-side validation against `cols` still never runs, because defect (3) is open and
AgentGraph still cannot send `source_metadata`; and the local preflight still covers only
single-item `{cols = [...]}` selectors. One rung of three, where there were none.

**Operational note, and it cost a false diagnosis once already.** The `RedisStreamSink` startup
crash is genuinely fixed at ExperimentTracking `b2f38c7`, but a tmux session holding the *old*
crashed shell will keep reporting "session exists" while nothing listens on the port. Restarting the
stack is not enough — the stale shell needs an explicit kill. "Session exists" is not "server
running".

Adjacent, and the same shape of trap: `agentgraph:tests/conftest.py:65` defaults `DASHIBOARD_URL` to
`:18632` while the stack's AUTH file exports `:8081`, so the live integration test **skips** in any
shell that has not sourced the auth file. Green output there means "not run", not "passed".

**The AgentGraph brief's author is no longer reachable.** `03-agentgraph-brief.md` was written by a
session that has since ended; none of the AgentGraph sessions live now wrote it, and they cannot
answer for its contents or its recommendation numbering. Attribute claims to the repository, not to
whoever is currently answering from it.

**AgentGraph's brief has gone stale in one respect.** Its line numbers are against `ae27633`, and
`agentgraph:main` has advanced since — their `ds-DashiUI` branch still sits at the commit it was cut
from. Whoever implements their recommendations should rebase first and re-resolve the citations.

**Ordering constraint — now released.** B3 landed on ExperimentTracking `ds-DashiUI` at `b2f38c7`,
so AgentGraph's switch from the `validate` method to the probe route is unblocked. The `validate`
method remains deliberately absent; `POST api/v1/probe` on train/evaluate is what
`validate_remote()` should call.

**And a breaking change went with it.** Unknown top-level parameters are now refused as `-32602`
naming the key and the accepted set, where `make` previously dropped them in silence. So AgentGraph's
`load_options` (`remote_procedure.py:258-262`) must be renamed to `source_options` — until it is,
every `dashiboard_train`/`dashiboard_eval` that sets reader options fails loudly instead of
mis-parsing the table. That is an improvement over defect (4) above, but it is visible immediately:
health goes green because `cards` works, and train/eval then fail.

---

## Sequencing

```
now ──┬── A1a → A1 → A2 → A3 ──────────┬── C1 → C2 → C7 → C3 ──┬── C5 ── embed
      │         └─ A3a, A3b, A3e       │                       │
      │                                │                       │
      │        A4, A5, A7 ─────────────┘                       │
      │        A6 ───────────────────────── B5 ────────────────┤
      ├── B1 (gates all of C) ─────────────────────────────────┤
      ├── B2, B3, B4 ──────────────────────────────────────────┤
      └── D (nexus 6 items, AgentGraph route) ─────────────────┘
                                                               │
                                       B6, B7 ─────────────────┴── retire DashiBoard server
```

**Critical path: A3.** It is the contract every renderer, validator and form depends on. A1a
precedes it absolutely; A3a, A3b and A3e are its sub-items and land with it — except that A3a's sibling half is already done (2026-09-09), so only its `$schema`/`dialect` pin still travels with A3, and that pin is gated by nothing.

**One cross-repo ordering constraint:** B3 must land **and be released** before AgentGraph switches
to the probe route.

## Working discipline

**Write fixtures, not arguments, about runtimes you cannot observe.** Four findings above were
reached by careful source reading and were wrong in the direction the reader was most confident
about: that the `$ref` sibling breakage was 2020-12-specific; that every nullable field carried a
discardable `default`; that the `required_columns` preflight was a check in place; and that `oneOf`
gave better errors than `if`/`then`. A five-line Ajv fixture and a warm Julia session settled all
four in minutes.

**State whether a claim was executed or read.** Every description in this folder of what code *does*
should be one or the other, marked. A path that has never run is a contract to satisfy, not
behaviour to rely on.

**Check whether a borrowed rule describes your mechanism.** "Merge, never replace" was sound advice
about AgentGraph's injection step. We construct rather than inject, so importing it would have
created the aliasing hazard it exists to prevent.

**Say whether a brief is a post-mortem or a reference, at the top.** They are the same document read
at two confidence levels, and nothing in the format distinguishes them. AgentGraph's brief was
commissioned as "an honest account of how that went", which produces a post-mortem — and was then
read as a specification, because it was the only account of a system nobody else could see. Three
times a defect of theirs was taken as evidence of the same defect here.

**Watch for synthesis that arrives after the verification.** The subtlest error in this
reconnaissance was not reasoning where measurement was available — it was measuring two things
correctly and then producing a tidy unifying claim that neither measurement supported. A3a and A3e
were each verified independently and then described as "the same aliasing from the other side",
which is false: A3a is two conflicting keys in one private dict, A3e is one mutable dict reachable
from twenty-four places. Nothing is shared in the first, nothing collides in the second, and neither
fix touches the other. The pull toward "these two things are one thing" arrives *after* the evidence
and therefore feels earned, which is precisely what makes it hard to catch.

**Attribute relayed measurements.** A result passed between sessions loses its provenance in one
hop: each of us restated the other's measurement in our own voice, and neither noticed until a
count needed checking. In a folder whose discipline is "executed or read", an unattributed relay
defeats the discipline exactly.

## Do not do

- ~~**Do not migrate the DashiBoard server to the group API.**~~ **REVERSED by the owner,
  2026-09-10.** The entry was right on its premise and the premise has changed. It assumed the new
  UI would serve against *ExperimentTracking*, leaving the DashiBoard server disposable. Under the
  standalone-first scope (§6) the new UI serves against the **DashiBoard server**, and will until B1
  and B6 land — which is after the team leader's review. Leaving it flat-only therefore means the
  standalone UI cannot preview the group vocabulary that §6's variable picker and C2 exist to
  author: measured against a live server, a flat card returns 200 while `inputs: [{cols: "TEMP"}]`
  and `inputs: [{groups: "weather"}]` both return **500**.

  Note also that the group API is **Pipelines'**, in this repository — ExperimentTracking inherits it
  by depending on Pipelines. So this is an inconsistency *inside* DashiBoard (Pipelines has a group
  API its own server does not call), not a cross-repository gap, and closing it is an update rather
  than a dependency.

  The update is small because the execution path already exists:
  `Pipeline(node_configs, group_configs, cols)` (`group_api/dag.jl:11`) resolves and validates, and
  `train_evaljoin!(repo, ::Pipeline, table, id_var)` (`pipeline.jl:232`) runs it. `report` and
  `visualize` take `p.nodes`. The genuine gap is **A4**, and `/get-card-ir` must serve the group
  dialect in the same change — the forms cannot author selectors until it does, which is B2's
  `schema_definitions(::VariableConfig)`, already implemented.
- **Do not add a per-field widget override.** §4 is deliberate; AgentGraph reports a per-field escape
  hatch would have metastasised.
- **Do not keep both schema dialects alive.** Serving one while validating with the other is what
  produced the current bug.
- **Do not annotate a built schema.** Construct it complete. See A3e for what happens otherwise.

## Decisions needed before specific commits

| Decision | Gates |
|---|---|
| ~~The IR's shape — being drafted by hand by the team leader~~ **CLOSED 2026-09-09.** Landed as `DashiBase/src/IR.jl`: `TrivialIR`, `BooleanIR`, `NumericIR{Int\|Float64}`, `StringIR`, `ReferenceIR`, `ArrayIR`, `ObjectIR`, `TaggedObjectIR`, `OneOrManyIR`, plus a `constraints` escape hatch. `TaggedObjectIR` is the variant selector and `OneOrManyIR` the one-or-many repeater, as first-class types rather than shapes to infer from `allOf`/`if`/`then` — which is the argument for serving the IR rather than making the renderer re-derive intent. | Nothing. A3's *emit* half remains — see Track A |
| Visualization: server-rendered Makie SVG, or client-side from data? | retiring the DashiBoard server |
| Filter annotations in DataIngestion or Pipelines? | A6 |
| ~~Is a DashiBoard node inspector inside nexus's assistant panel ever wanted?~~ **ANSWERED 2026-09-09: no.** See `01-decisions.md` §12, moved to *Settled by reconnaissance*. | Nothing. The framework is settled: SolidJS stays |
