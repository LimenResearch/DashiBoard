# `through` chains that cannot be resolved — report them, do not crash

Status: **proposed**, waiting for the Pipelines work in progress. Server-side only; the UI needs
no change for option B, and one small request change for option A.
Raised from the UI todo (`.superpowers/sdd/todos/2026-09-17-needs-attention-from-verdicts.md`, item 3g).

## The fault, measured 2026-09-18

A selector item may qualify a column with a `through` chain: `{cols = "PRES", through = ["r"]}`
names the column `PRES` *as renamed by* node `r`. Resolution concatenates the `suffix` of every
node in the chain (`Pipelines/src/group_api/deps.jl`, `pass_through`):

```julia
# TODO: more general definition
function pass_through(x::AbstractVector, is::AbstractVector, nodes::AbstractVector)
    isempty(is) && return x
    suffix = join((node.card.suffix for node in view(nodes, is)), "_")
    return join_names.(x, suffix)
end
```

Measured against a running DashiBoard (through the dev proxy, `POST /probe-pipeline`):

| document | reply |
|---|---|
| `r` rescales `PRES` (suffix `z`); `s` reads `{cols:"PRES", through:["r"]}` | valid; `s` inputs `["PRES_z"]` |
| `sp` is a `split` card; `r` reads `{cols:"PRES", through:["sp"]}` | `valid:false`, `errors:["FieldError: type Pipelines.SplitCard has no field \`suffix\`, available fields: \`method\`, \`order_by\`, \`group_by\`, \`output\`"]`, **`issues:[]`** |
| same chain on a lone selector, `partition: {cols:"cbwd", through:["sp"]}` | the same `FieldError`, `issues:[]` |

The `FieldError` reaches the client as a document-level sentence with no pointer, so no card or
group can carry it. The UI prints it under the Run button since 2026-09-17, which is better than
nothing and worse than a mark on the item that caused it. `POST /evaluate-pipeline` fails the
same way.

## Why

Two facts, both by design, that were never reconciled:

1. `pass_through` assumes every node in a chain has a `suffix`. Five card types do
   (`rescale`, `interp`, `glm`, `gaussian_encoding`, `streamliner`, plus a `WildCard` with
   `needs_targets`). Four do not: `split`, `cluster`, `dimensionality_reduction`,
   `window_function` carry `output` instead. Those four make a *new* column, so "`PRES` as
   renamed by `split`" has no meaning; they are referred to with `{nodes = "sp"}`.
2. The `through` vocabulary admits every node. `variable_item_IR` (`group_api/schema.jl`) builds
   `through` as `ArrayIR{String}(items = NODE_DEF)`, and `NODE_DEF` is the enum of *all* node
   ids. Schema validation therefore passes the chain, and the fault surfaces only when the
   `Context` is built — as an exception, not an issue.

So the document is schema-valid and unbuildable, and the gap between the two is reported the way
every unanticipated exception is: `failure_report` with the exception's text.

## What a fix has to deliver

- The fault is reported as an **issue with a pointer** to the offending `through` entry, in the
  shape every other issue has (`pointer, reason, severity, found, allowed, missing, related,
  message`), from both `/probe-pipeline` and `/evaluate-pipeline`.
- No `FieldError` in `errors` for this case.
- Passable chains are unaffected: `test/groups.jl` (`groups.toml` has `through = ["rescale"]`)
  stays green.

## Options

### B — validate the chain, report with a pointer (recommended)

Add a graph-level check beside schema validation: every `through` entry must name a node whose
card can be passed through. "Can be passed through" is a property of the card type, so make it
one: a method such as

```julia
passable(::Card) = false
passable(c::RescaleCard) = true          # …and the other suffix-bearing types
```

or, equivalently, `hasfield(typeof(card), :suffix)` — but a method is the honest interface,
since a `WildCard` has the field and only sometimes a value.

The check runs where the whole document is known and pointers can be built:
`validate_pipeline_schema` walks nodes and groups with their document positions, and the
hand-built issues in `DashiBoard/src/handlers.jl` (`empty_group_issues`, `overwrite_warnings`,
`unproduced_issues`) show the target shape. One issue per offending entry:

```julia
(;
    pointer  = "/nodes/1/card/inputs/0/through/0",     # or /nodes/1/card/partition/through/0,
                                                       # or /groups/g/0/through/0
    reason   = "through",
    severity = "error",
    found    = "sp",
    allowed  = passable_ids,                           # the node ids a chain may pass through
    missing  = String[],
    related  = String[],
    message  = "`sp` cannot be passed through: it makes a new column (`output`) rather than " *
               "renaming its inputs — refer to it with `nodes = \"sp\"` instead",
)
```

`allowed` lets a client offer the alternatives; the message says what to do instead.
`pass_through` itself can then stay as it is, or gain an `ArgumentError` with the same sentence
as a backstop for callers that bypass validation.

Placement: this is Pipelines' rule (`pass_through` lives there, and the group dialect's
validation does too), so the check belongs in `Pipelines/src/group_api/schema.jl` next to
`validate_pipeline_schema`, and DashiBoard's probe and run handlers forward it like the schema
issues. If it is more convenient to build the issue in `handlers.jl` alongside
`empty_group_issues`, the shape above is the same; only the `passable` method must come from
Pipelines.

What the UI does with it, unchanged: a pointed error issue is shown on the card or group it
points at (`fieldPath(pointer)` names the field), Confirm rejects the item with it, and a failed
run marks the item. "Needs attention" names the item instead of "the document".

### A — make it unrepresentable in the vocabulary (optional, later)

Narrow `through`'s enum to passable node ids, so a client's chain builder never offers `split`.
This needs the server to know each node's *card type* when it builds the defs, and today
`POST /get-card-ir` receives node **ids** only (`handlers.jl`, `maybe_strings("nodes")`; the
UI's `vocabulary` memo in `processing.tsx` sends `{cols, nodes, groups}`). So A is a two-sided
change: the request carries `nodes: [{id, type}]` (or a separate `through: [ids]`), and
`VariableConfig` gains the passable subset, used only for `through`'s items — `NODE_DEF` itself
must keep every node, because `{nodes = "sp"}` is exactly how an `output` card is consumed.

A does not replace B: an imported document can still carry a chain the vocabulary would not
have offered, and B is what reports it. Do B first; A is polish.

### C — generalise `pass_through` (not recommended)

Define what "`PRES` through `split`" means. There is no such thing: an `output` card does not
transform its inputs column-wise. The `# TODO: more general definition` is about suffix
composition across card types, not about admitting these four.

## Tests (Pipelines)

- A document with `{cols = "PRES", through = ["sp"]}` where `sp` is a `split` card: validation
  returns one issue, pointer `/nodes/1/card/inputs/0/through/0`, `reason == "through"`,
  `found == "sp"`; no exception is thrown by `Pipeline(...)` on this input — or, if the backstop
  is kept, its message is the sentence above and never a `FieldError`.
- The same on a lone selector (`partition`) and on a group item: pointers
  `/nodes/1/card/partition/through/0` and `/groups/g/0/through/0`.
- A chain through `rescale` still resolves to `PRES_<suffix>` (`test/groups.jl`, unchanged).
- A chain of two, `through = ["r", "sp"]`: the issue points at index 1, not at the chain.

## What was considered and set aside on the UI side

A UI-only mitigation exists: narrow the chain builder's options to nodes whose card IR declares
`suffix`, the way `withoutOption` already keeps a card from naming itself. Set aside because it
copies a server rule into the client (the picker's design notes forbid exactly that), and because
it would be wrong the day `pass_through` is generalised. It becomes a harmless no-op if A is
done, and unnecessary once B is.
