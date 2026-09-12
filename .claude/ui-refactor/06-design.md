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
| A7 | ~~Give `SchemaValidationError` a JSON Pointer and a `related` array~~ **DONE 2026-09-10** — `Pipelines.issue_report` + `issues` on the probe route | Two entries in the detail below were written from reading and are **corrected there by fixtures**: array steps in `SingleIssue.path` are 1-based so the pointer conversion is not mechanical, and `required` carries every required name rather than the missing one. Unproduced references share the shape but address the **node**, not the selector item that named it — resolution keeps no provenance back to the item. Originally: mostly plumbing — see below. **Scope updated 2026-09-10:** it stays a separate item, but its corpus is now *two* error sources, not one — schema-validation failures **and** A10's unproduced-reference failures — and A10's probe route is its delivery vehicle. Both already know their node and field, so they address by the same pointer scheme; what differs is only where the failure is detected. |
| A8 | Validate the **node wrapper**, not only `node["card"]` | A typo like `trian = false` is accepted and silently ignored today. **Measured 2026-09-10, and it is worse than "ignored":** `DashiBoard/test/static/pipeline.json` passes `by` to two split cards, but `SplitCard` defines `group_by`. The flat `Card` constructor drops the unknown key, so `group_by` comes out `String[]` — those cards partition *globally* instead of by `cbwd`. Two documents, one correct and one typo'd, are indistinguishable to the flat constructor and produce **different pipelines with no error at either point** — the failure mode is a changed result, not a missing one, so nothing downstream can detect it. **Scope of the instance:** the only occurrence found is that test fixture, whose assertion checks the output column exists rather than how it partitions, so no real results are implicated; what it demonstrates is the hazard. **Nothing was broken by the migration** — verified on untouched `origin/main`, the group path already rejected `by` and accepted `group_by`, the `Card` construction path is unchanged, and the old `evaluate_pipeline` handler ran no validation at all. The check was intact and effective; the server bypassed it. Migrating turned it on. ExperimentTracking confirmed its own registry cannot hold such a document — validation precedes storage on the only path that writes there — so the exposure is documents authored through the flat path and persisted elsewhere. This is a correctness argument for the group API independent of any UI. |
| A9 | Fail closed when the variable context is missing | `VariableConfig`'s `nothing` means *unconstrained*, so omitting `cols` validates everything. |
| A10 | ~~Check that every resolved reference is actually produced, and serve it from a probe route~~ **DONE 2026-09-10** — `unproduced_references` + `POST /probe-pipeline` | Closes the systemic finding below rather than working around it in one client. See detail. |

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
path, so the pointer alone does not identify the control; the form must join the two. That is where
`related` earns its keep beyond the `weights`/`inputs` pair.

**Path stability is confirmed to three levels.** `"[method][dissimilarity][p]"` is the deepest case
in the card set and converts to `/method/dissimilarity/p`.

#### Two corrections, executed 2026-09-10

Both entries above were written from reading. Fixtures run against JSONSchema.jl before
implementing contradict them, and both corrections are load-bearing — a form built on the read
version points at the wrong control.

- **`path` indexes arrays the Julia way, so the conversion is not mechanical.** Measured: with
  three inputs and the *third* bad, `path == "[inputs][3][cols]"`. A JSON Pointer counts from zero
  and must say `/inputs/2/cols`. Object keys convert unchanged; array steps subtract one. Worse,
  which steps are array steps **cannot be read off the path** — `"1"` is a legal object key — so
  the conversion has to walk the validated document alongside the path and ask what it finds.
  `json_pointer(base, path, object)` does exactly that.
- **`required` carries every required name, not the missing one.** Measured, for a `rescale` card
  missing `method`: `val == ["method", "inputs", "type"]`, and `x` is the object. The missing name
  is `setdiff(val, keys(x))`. A form handed `val` verbatim tells the user that method, inputs and
  type are all required, two of which they already supplied — which is a complaint, not a
  correction, and the exact failure mode A7 exists to end.

**Where it landed.** `Pipelines.issue_report(::SchemaValidationError)` returns
`(pointer, reason, found, allowed, missing, related, message)`. `SchemaValidationError` now carries
the document-rooted pointer base and the validated fragment, because a card-local pointer is
ambiguous the moment a document holds two cards: a card failure bases at `/nodes/{i-1}/card` and a
group failure at `/groups/{name}`. `POST /probe-pipeline` serves it as `issues`, always present so
a client reads one shape rather than branching on which half of the route answered. Pinned in
`Pipelines/test/groups.jl` ("A7: a validation failure as data", 20 assertions) and end to end in
`DashiBoard/test/dashiboard.jl`. **Done.**

### A10 in detail — the check nothing performs, and where it belongs

**The gap.** `through` builds a column *name* by concatenating the suffixes of the nodes it names.
Validation checks only that the *base* column exists in the source. So a chain naming a column no
node produces — `{cols = "PRES", through = ["rescale", "log"]}`, where `log` consumes `No` and emits
only `No_log` — is **accepted**, and fails later inside a task with a `TaskFailedException` naming
neither the column nor the node. Verified by execution; pinned in
`Pipelines/test/groups.jl`. It is the sharpest instance of this document's systemic finding, because
the reference is never written down anywhere — it is computed.

**Where the check does *not* belong: the UI.** The obvious fix is for the picker to compute what a
chain resolves to and offer only chains that exist. That would be a second implementation of
`pass_through` in TypeScript — a second source of truth for a naming rule, which is the duplication
this refactor exists to remove. **The UI writes the TOML; DashiBoard resolves it.** (Owner,
2026-09-10.)

**The check is computable server-side from what construction already produces**, using only public
accessors and no re-derivation of the naming rule — by the time you compare, Julia has already
resolved. Measured on the `groups.toml` fixture:

```
GOOD  through = [rescale]        pca inputs = ["PRES_rescaled"]       ∈ pool
BAD   through = [rescale, log]   pca inputs = ["PRES_rescaled_log"]   UNPRODUCED
```

where the pool is the source columns together with what the nodes emit — `get_node_inputs` and
`get_node_outputs` over the resolved `Pipeline`.

**Correction to an earlier claim here.** I wrote that scoping the pool **topologically** was needed,
because a global pool would admit a node consuming a column produced after it. That case cannot
arise: `through` creates a dependency edge like any other reference
(`append_edges!(dp, through, i)`, `group_api/deps.jl`), so every produced column a node consumes
comes from a node it depends on. The implementation still walks by layer — it is the natural
traversal and costs nothing — but that is defence, not a fix. The real failure is simply *nothing
produces this name*. And a `through` naming its own consuming node is already caught as a cycle, so
the uncovered set is exactly the acyclic-but-unproduced chains.

**Implemented 2026-09-10.** `Pipelines.unproduced_references(p, available)` returns node indices
paired with the inputs nothing makes available, and `POST /probe-pipeline` serves it. The route
constructs without executing, reads only the source table's column names via `colnames`, and
materialises nothing — safe to call on every edit. It **reports rather than throws**: a schema
failure comes back as `valid = false` with the message, because a probe that answers 500 tells a
form nothing it can render.

**The route.** A probe that constructs a `Pipeline` without executing it and returns per-node
resolved inputs and outputs plus any unproduced references. Construction is the cheap half;
`evaluate-pipeline` already does it before running anything. The UI then posts the document and
*displays* what Julia resolved, owning no part of the rule. It is also the vehicle for A7 — see that
entry — and it mirrors ExperimentTracking's `probe`, which returns `{valid, source_vars, output_vars}`
for its own methods, one layer up.

**Value beyond this UI.** AgentGraph's `_dashi_preflight` exists to catch exactly this class and
fails open after the format break. A server-side check makes that preflight redundant rather than
requiring it to be fixed.

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
| B2 | **Partly done upstream, 2026-09-10.** The Pipelines half is built and no longer ExperimentTracking's to write: `ir_definitions(::VariableConfig)` returns the group `$defs` as IR nodes — `node`, `group`, `col`, `variable`, `variables`, `nonempty_variables` — and `schema_definitions(::VariableConfig)` is now its projection through `json_schema`, so the two cannot drift, exactly as for the flat pair. DashiBoard's `POST /get-card-ir` serves it, taking `{cols, nodes, groups}` rather than a flat variable list: which nodes and groups are referenceable depends on the document being edited, not only on the source, so the UI re-fetches when a node is added or renamed. What remains for ExperimentTracking is exposing the same over its own wire. | — | — |
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
| C8 | **Key a dispatch table on its union where one exists; require a fallback where it does not** | — |
| C9 | **Sync the host's type scale. Do not sync a density number — there isn't one** | — |
| C3 | Canvas: auto-laid-out DAG, side editing panel, no stored positions | A4 |
| C4 | Connect source, results panes | B7 |
| C5 | `/embed` route and the `postMessage` contract. **Scope corrected and theming settled, 2026-09-09** — see *C5 in detail* below. The contract is far thinner than this row originally implied. | Track D |
| C6 | Runtime API base address, never a build-time constant | — |
| C7 | Validate with the schema; attach errors to IR entries by pointer | A3, A7 |

---

### C8 in detail — exhaustive dispatch, borrowed from a live bug next door

Two components here dispatch on a closed set: C1 renders per IR entry kind, C2 per selector kind
(`cols`/`nodes`/`groups`). Both are exactly the shape that produced a shipped defect in
nexus-weaver-pro on 2026-09-10, documented in `05-nexus-weaver-brief.md` §3c.

Their `GraphMinimap.dotColors` was `Record<string, string>`, keyed on node types that no longer
existed while the union had gained one the table lacked. The missing key resolved to `undefined`,
SVG fell back to its default, and **12 of 22 nodes painted black** — legible enough on a light card
to look deliberate, invisible on a dark one. The table had drifted from its union in both directions
at once, with no compiler complaint.

**The rule: key on the union *where there is one*.** A missing variant then becomes a build error
rather than a silent fallback. Their sweep found the same shape in three more places, each latent,
and drew out the uncomfortable part — the two *guarded* maps were a throwaway mock page and a
dialog, while the one that shipped unguarded was the live rendering component. Defensive coding
landed where it mattered least.

**Refined 2026-09-11, and the refinement matters here more than there.** Stated as an absolute —
"never key on `string`" — the rule pushes you to invent unions the API does not have. Three of their
tables correctly key on `string`, because the server types the field as a bare string or the domain
is genuinely open; what those need is a *fallback*, not a union.

For us the line falls in a specific and checkable place:

- **IR entry kind and selector kind are closed**, server-defined and finite. Key on the union; a new
  kind must fail the build. This is also what protects the property C2 depends on — selector-kind
  must be **unrepresentably** wrong, and a table tolerating an unknown kind reintroduces exactly the
  state the picker exists to make impossible.
- **Card type is open by design.** `register_card` and `register_wild_card` are public, and
  `WildCard` exists so a downstream package can add a type `Pipelines` has never seen. A renderer
  dispatching on card type must therefore have a fallback and must render something honest for an
  unknown one — never a blank panel.

### C8 addendum — two Tailwind traps that are not ours, and one that is

nexus-weaver-pro reported three findings on 2026-09-11. Checked against our tree: we are SolidJS +
Tailwind with **no shadcn, no `tailwind-merge`, no `cva`**, and no `App.css`, so none applies as
stated. Two generalise to plain Tailwind and are worth knowing before C1 and C2 are written.

- **A parent's arbitrary-variant utility outranks a child's own class.** `[&_svg]:size-4` on a
  parent compiles to a descendant selector at specificity (0,1,1); the child's `h-3` is (0,1,0), so
  the parent wins. They had 39 call sites whose icon sizes were all dead, every one rendering 16px
  in a 24px button — invisible in review, because the child's className reads correctly. If we write
  arbitrary variants targeting descendants, the size must live on the parent variant.
- **Responsive variants do not collapse with base utilities.** `text-xs` and `md:text-sm` are
  different groups; both survive, and above the breakpoint the media query wins. Their compact
  inputs were compact only on phones. This is plain CSS and applies to us whether or not we ever add
  a class merger.

Not applicable, recorded so nobody re-derives it: their ag-grid Theming API advice is conditional on
ag-grid v33+, and we are on `@ag-grid-community/core` ^32.3.9 — legacy mode. And the unimported
`App.css` finding is about their Vite scaffold; we have only `index.css`, and our density notes live
in this plan rather than in a stylesheet.

### C9 in detail — there is no density convention to sync

**Corrected 2026-09-11 by nexus-weaver-pro, and it says close to the opposite of what this row said
yesterday.** The figures in `05-nexus-weaver-brief.md` §3b came from a single-line grep that missed
64 of 91 multi-line `<Input>` tags. Re-measured by brace-matching each opening tag:

| Control | n | Distribution |
|---|---|---|
| Button | 186 | `h-9` ×80 (77 via `size="sm"`), `h-7` ×33, `h-10` ×22, `h-6` ×20, `h-8` ×15, `h-5` ×11, `h-4` ×5 |
| Input | 91 | `h-10` ×54 (unsized default), `h-8` ×21, `h-7` ×11, `h-6` ×4, `h-9` ×1 |
| SelectTrigger | 33 | `h-10` ×18 (unsized default), `h-8` ×7, `h-9` ×4, `h-7` ×4 |

**Compact was a minority local override — 36 of 91 inputs — not a convention.** And it is not drift
within files: it is *two* conventions split by feature area. Of 31 files rendering an Input or
SelectTrigger, 14 are entirely compact, 13 entirely default, 4 mixed. The rule you would guess does
not hold — their densest surface is a dialog, and so is one of their roomiest. What it tracks is
which feature was built when.

**Retracted 2026-09-12: the type scale is not safe to sync either.** The figures above were the
second bad census from the same source and were withdrawn by it. Re-measured, **475 of 921 sized-text
tokens — 51% — are arbitrary values below `text-xs`, in five distinct sizes, across 65 files.** The
type scale is the *least* consolidated thing in that system, not the most.

The cause was a regex: `\btext-(\[[0-9]+px\]|xs|sm|…)\b`, where `\b` cannot match between `-` and
`[`, so the alternative naming the arbitrary form never matched. The pattern *said* it counted
arbitrary sizes and returned none, and the tidy output was read as a tidy codebase.

**Calibration for anyone implementing against `05-nexus-weaver-brief.md`:** two of its censuses have
now been wrong, in different ways, and both looked clean. Its *token list* was read directly from
`index.css` and remains reliable; its *counts* should be re-measured before anything is built on
them. That is not a criticism of the brief — both errors were caught and corrected by its author —
but a plan should not carry a number it has not seen produced.

**Do not pin against a control height.** They have since made both conventions *expressible* — size
recipes on Input and SelectTrigger — so choosing between them is a `defaultVariants` edit on two
files rather than a 31-file sweep, and they have deliberately not chosen, because it is a product
decision that is now cheap and reversible. A UI that hard-codes to today's majority will be wrong if
that flips, at no warning.

The general lesson is worth more than the numbers: **a census taken with a line-oriented grep
undercounts multi-line tags silently**, and the undercount is not random — it concentrated in
exactly the files whose markup had grown complex enough to wrap, which is a population with its own
conventions.

**[2026-09-12] The vocabulary to adopt.** nexus-weaver-pro has since tokenised density and proposed
a shared naming, offering to rename if it collides with ours. It does not — we have nothing to
collide with, which is the cleanest possible position to adopt from. Nine properties on `:root`,
shaped `--control-<property>-<step>`:

| | `default` | `sm` | `xs` |
|---|---|---|---|
| `--control-height-*` | `2.5rem` | `2rem` | `1.75rem` |
| `--control-text-*` | `0.875rem` | `0.75rem` | `0.75rem` |
| `--control-leading-*` | `1.25rem` | `1rem` | `1rem` |

Their step names match their variant API, so `size="sm"` and `--control-height-sm` are visibly the
same thing. **Our old frontend's "compact" is their `xs`.** These are geometry: `:root` only, never
`.dark`, and they join `--radius` as documented exceptions to any palette-parity test — a test that
checks `:root`/`.dark` parity without an allowlist will fail on them and look like a parity bug
rather than a category difference.

**Three properties per step, not two — and the third is the one that bites.** Tailwind's `text-xs`
sets font-size *and* line-height. The arbitrary form needed to read a custom property,
`text-[length:var(--x)]`, sets **font-size alone**, so a naive swap silently drops the line-height
and the control inherits whatever the surrounding page had. It looks right on the page it was
written for and drifts elsewhere — the same failure shape as a Graphviz `<text>` inheriting black.
Worse, the combined syntax `text-[length:var(--a)]/[var(--b)]` **does not compile in Tailwind 3.4**
and emits nothing, with no error; `leading-[var(--b)]` as a separate utility does. **We are on
Tailwind ^3.4.19, so this reaches us directly.**

**Our Button needs no reconciling.** They left theirs literal because its ladder runs `h-5` to `h-11`
across six text steps and does not map onto three density steps, and asked whether ours lines up.
It has no ladder at all: `frontend/src/components/button.jsx` is one size, padding-based
(`py-2 px-4 text-xl`), and the whole frontend contains two `h-7` and no other height class. So there
is nothing to align — and nothing to preserve either, since `text-xl` on a button is far rougher
than either of their conventions.

**Steal their pin test, for the reason they give.** Nine assertions tying each token to the Tailwind
size it stands in for, checked in the built CSS at each link rather than reasoned about. Their
rationale generalises well past CSS: *the entire point of a token is that it can be varied, which
means nothing else in the system will ever notice if it is varied by accident.* Tokenising removes a
guard rail at the same moment it adds a capability, and the pin is what puts the rail back.

### C2 in detail — the variable picker

Designed with the owner on 2026-09-10. Every claim below was established by running it; the cases
are pinned in `Pipelines/test/groups.jl`, "selector cases the picker must express".

**What a field holds.** One *ordered list* of items. An item is exactly one of `cols`/`nodes`/
`groups` (the `oneOf` gate), each **one-or-many**, plus an optional ordered `through`.

**Four facts that decide the design.**

- **A ≡ B.** `[{cols = ["PRES","TEMP"]}]` and `[{cols = "PRES"}, {cols = "TEMP"}]` resolve
  identically. The item boundary carries no meaning *until* a `through` differs — and then it
  carries all of it.
- **The same value can appear twice under different qualifications.**
  `[{cols = "PRES", through = ["rescale"]}, {cols = "PRES"}]` resolves to
  `["PRES_rescaled", "PRES"]`. **Any UI modelling a field as "a set of values with attributes"
  cannot express this** — there is nowhere to put the second `PRES`. This is what rules out both a
  flat categorised combobox and a per-kind bucket layout.
- **Order is meaningful**, across kinds and within one. Reversing two items reverses the resolved
  column list. Until §12 designs out the positional `weights` rule, a UI that concatenates by kind
  silently changes which weight lands on which column.
- **`through` is an ordered list of nodes**, whose suffixes concatenate: `["rescale","log"]` names
  `PRES_rescaled_log`, and `["log","rescale"]` names something different. Chains execute — verified
  end to end, a three-node chain producing `TEMP_a → TEMP_a_b → TEMP_a_b_c`. An empty `through`
  resolves identically to an absent one.

**The design: group by qualification, not by value.**

- A **Direct** panel with three subpanels — `columns`, `groups`, `nodes` — holding items with no
  `through`.
- *n* **Through** sections, each headed by an ordered node chain and containing the same three
  subpanels.
- Because an empty `through` is equivalent to an absent one, **Direct is a Through section with an
  empty chain**: one component, used four ways, which is what §6 asks for.

This is what makes the duplicate-value case fall out — `PRES` appears in Direct *and* in
Through[rescale], with no duplicate inside either control.

**Two constraints on the implementation.**

1. **The panels are a view over one ordered list, not three lists.** The store keeps document
   order; each subpanel shows the items of its kind in that order; adding appends. Order is then
   preserved by construction, and reordering is simply not offered — acceptable while §12 is open,
   and revisitable if `inputs` stays ordered.
2. ~~**The chain control must be constrained to chains that exist.**~~ **WITHDRAWN 2026-09-12. It
   contradicted a principle stated elsewhere in this same document, on the same day it was
   written.**

   A10's detail section already says, attributed to the owner and dated 2026-09-10: *"Where the
   check does not belong: the UI. The obvious fix is for the picker to compute what a chain resolves
   to and offer only chains that exist. That would be a second implementation of `pass_through` in
   TypeScript — a second source of truth for a naming rule, which is the duplication this refactor
   exists to remove. **The UI writes the TOML; DashiBoard resolves it.**"*

   C2's clause below asks for exactly that computation. Both were written on 2026-09-10 and the
   document has disagreed with itself since. This is not the owner changing position — it is C2
   being wrong from the start, and the contradiction surviving because each section was read on its
   own. The original is kept below because its reasoning about the *failure* is still right; only
   its remedy is withdrawn.

   > `through` builds a column *name* by concatenating suffixes; validation checks only that the
   > *base* column exists. A chain naming a column no node produces is **accepted** and fails later
   > inside a task, naming neither the column nor the node — `06`'s systemic finding landing on a
   > concrete case, and the sharpest instance of it, because the reference is never written down.
   > The UI holds the whole document and therefore knows every node's suffix and outputs, so it can
   > offer only chains that resolve to something a node actually emits, and show the resulting name
   > as the chain is built (`TEMP → r1 → r2 = TEMP_a_b`). That converts a late, uninformative SQL
   > failure into an empty dropdown. **This is the one place the UI can compute an answer the server
   > will not check.**

   **What the document contains, which was never in question and is worth stating anyway:** the
   selector form and only the selector form — `{cols = ["No","year"]}, {cols = "month", through =
   "log"}`. Never `month_log`. The group dialect has always been a set of *references* that
   DashiBoard resolves; a document holding resolved names would have resolved away the vocabulary
   the picker exists to author.

   **What is withdrawn:** the UI showing a resolved name, anywhere — including the chain composer's
   `= TEMP_a_b` preview, which is what the original clause specifically asked for. Producing that
   string requires implementing suffix concatenation in the browser, and that is a second source of
   truth for a naming rule DashiBoard owns. It is the same duplication A10 was created to delete,
   and the same shape as every other rule this project has found written down twice.

   **What that costs, stated plainly.** The original remedy was *prevention*: filter the offer, so a
   chain that names nothing is simply not on the menu. Without client-side naming the UI cannot
   filter, so the protection moves from prevention to **reporting** — and the empty dropdown this
   clause wanted is not available.

   **What delivers it instead: A10, which did not exist when this was written.** `POST
   /probe-pipeline` runs on every edit and reports unproduced references, addressed by JSON Pointer
   (A7). So a chain naming nothing is caught *before a run*, which was this clause's actual goal —
   later than an empty dropdown, far earlier than a failure inside a task, and it is the server's
   own answer rather than a browser's guess at it.

   **If prevention is wanted back**, the way to get it is for the *server* to enumerate the chains
   that resolve, not for the UI to work them out. That is the only version of filtering that does
   not duplicate the rule, and it is server work rather than UI work.

What *is* caught server-side: a `through` naming the consuming node makes the graph cyclic and is
rejected. So the unconstrained control's failure mode is narrower than "anything goes", but still
covers every chain that is acyclic and unproduced.

**Asymmetry worth budgeting for:** Direct needs none of this — a column either exists in the source
enum or does not. The Through section is genuinely more work than Direct, not a repeat of it.

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
- **Density rides this same payload — it needs no new channel, but it does need this one.**
  nexus-weaver-pro tokenised control density on 2026-09-12 as nine `--control-<property>-<step>`
  properties, and suggested density may need no transport at all, because a custom property
  inherits: a host that sets the palette on a wrapper sets density the same way, in the same place.
  **That is true same-document and false across a frame** — which is the first line of this section.
  Their suggestion is written from the host's position, where there is nobody to receive density
  from. For us the correct reading is narrower and still useful: density needs no *new* transport,
  because whatever carries the palette carries this too — no URL parameter, no second channel.

  **Say "a payload someone will build", not "one that exists".** An earlier draft of this bullet said
  density was nine more entries in a payload that already crosses. It is not: nothing crosses today.
  Verified in the host's tree — no `postMessage` in `src/`, no `<iframe>` outside a comment about
  byte-serving endpoints, no `getComputedStyle` export path, and `/dashiboard` still an 820-line mock.
  That contradicted the first line of this very section, which says the contract is designed rather
  than discovered. The cost of adding density is still near zero; the point is that a plan reading
  "already crosses" will not budget for building the sender.

  The inheritance property is worth having for a different reason. **Inside** the frame, a subtree
  can redeclare `--control-height-default: var(--control-height-sm)` and every control within
  follows without one call site naming a size. That is what makes "each surface declares its density"
  expressible rather than a matter of discipline, and it is directly useful for a dense side panel
  beside a roomy canvas.
- **Enumerate the token set dynamically; never list the properties by name.** Density was missing
  from this contract for exactly one reason: colour was enumerated by hand, and nobody conceived of
  density as a thing that varies. A hand-written list reproduces that failure the next time a
  category appears — spacing, motion, whatever it turns out to be. It is the same shape as a class
  naming an uninstalled animation: **a payload omitting a token looks identical to a payload that is
  complete.** Read the properties off the computed root rather than from a literal.
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

**A named mechanism stops being a question.** The sharpest failure in this exchange was not a
missed measurement but a completed one. nexus-weaver-pro diagnosed correctly that values below
Tailwind's scale can only be arbitrary values, that arbitrary values collide with nothing, and that
this "is what let them multiply" — then removed the symptom from 48 buttons, left the cause in 65
files, and reported the type scale as holding in the same message. Writing the mechanism down made
it feel handled. **After naming a cause, ask where else it applies before treating it as closed** —
the diagnosis is the beginning of the search, not the end of it.

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
