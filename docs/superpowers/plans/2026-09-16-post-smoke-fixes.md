# Post-smoke fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the fixes the 2026-09-16 smoke run asked for — a server issue model with severity, definition-time errors for empty groups and card-less documents, `null` for non-finite floats, a warning for overwritten columns, run failures placed on the cards, cascading deletes and keep-and-mark for dangling references, a session gate with Start over, and a card header that folds instead of overflowing.

**Architecture:** Server first (Julia: `Pipelines` and `DashiBoard`), so every UI task consumes an interface that already exists. The one interface change is `severity` on issues; the empty-group check and the overwrite warning are new issue kinds emitted by the DashiBoard handlers; `json_response` and `fetch_data` stop letting non-finite floats through. The UI then routes run-failure issues into `PROBE_STORE` so cards show them as probe findings, replaces its own `checkGroup` with the probe's answer, cascades references in the store, marks references the vocabulary cannot name, resets filters on a table change, adds `session.ts` with a gate and Start over, and lets the card header wrap.

**Tech Stack:** Julia (HTTP.jl 2.6.7, JSON.jl 1.8, DuckDB, FunSQL), SolidJS 2.0.0-rc.6, @solidjs/router 2.0.0-next.21, Vitest 4 + jsdom, pnpm, ag-grid 32.3.9 (infinite row model).

**Spec:** `docs/superpowers/specs/2026-09-16-post-smoke-fixes-design.md`

## Global Constraints

- **Commits:** one commit per task on the side branch (`sdd/post-smoke`), never on ds-DashiUI; nothing is pushed by a task. Commit messages end with a blank line then `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- **Every change outside `dashiboard-ui/` carries its functional justification in the code** — the function's docstring, or a comment at the change — saying what it does and why it is needed (the observed failure, the case it serves). Not only in the commit message. The task reviewer checks it. (Spec §7.)
- **Julia commands run from the repository root.** DashiBoard suite: `DASHIBOARD_CACHE=/tmp/dashi-test-post-smoke julia --project=DashiBoard/test DashiBoard/test/runtests.jl > <log> 2>&1` — full output to a file, read the file; never grep-filter a run you are diagnosing. Pipelines suite: `julia --project=Pipelines/test Pipelines/test/runtests.jl > <log> 2>&1`. First runs precompile (minutes): use a long timeout. If `--project=DashiBoard/test` complains about a missing dependency, `julia --project=DashiBoard/test -e 'using Pkg; Pkg.resolve()'` once.
- **UI commands run from `dashiboard-ui/`** with pnpm: `pnpm exec vitest run --reporter=dot`, `pnpm exec tsc --noEmit`, `pnpm run lint` (0 errors), `pnpm run build`. All four after every UI task. The suite must stay at **0 `[STRICT_READ_UNTRACKED]` lines**.
- **Solid 2 rules:** `createEffect(compute, effect)` — every reactive read goes in `compute`; store setters take a function; `createMemo` for derived values; tests `await flush()` after interactions; `class` takes arrays/objects.
- **Tests assert; they do not print.** Every new assertion is mutation-tested before a task is declared done: change the code so the claim is false, confirm the test fails, restore, and paste both outputs in the report.
- **Issue shape** (server → UI): `{pointer, reason, severity, found, allowed, missing, related, message}`; `severity` is `"error"` or `"warning"`, absent means `"error"`. Warnings never make `valid` false.
- **Storage keys:** `dashi.loader`, `dashi.filters`, `dashi.cards`, `dashi.confirmations`, `dashi.tab`, and (new) `dashi.gate`. `resetSession` removes every key starting with `dashi.`.

---

## File map

| file | task | responsibility |
|---|---|---|
| `Pipelines/src/group_api/dag.jl` | 1 | `init` so zero nodes build |
| `Pipelines/test/groups.jl` | 1 | card-less `Pipeline` builds |
| `Pipelines/src/group_api/schema.jl` | 2 | `severity` on `issue_report` |
| `DashiBoard/src/handlers.jl` | 1–4 | `empty_group_issues`, `overwrite_warnings`, probe/evaluate wiring, `fetch_data` non-finite |
| `DashiBoard/src/middleware.jl` | 4 | `json_response` writes `null` for non-finite |
| `DashiBoard/test/dashiboard.jl` | 1–4 | live-server tests |
| `dashiboard-ui/src/probe.ts` | 5 | `askProbe`, `usableProbe` — one place |
| `dashiboard-ui/src/stores.ts` | 5, 7 | `severity`, `reportRunIssues`, `issuesForGroup`, cascading references |
| `dashiboard-ui/src/left-tabs/results.tsx` | 5 | run failures → `reportRunIssues`, pane text |
| `dashiboard-ui/src/left-tabs/processing.tsx` | 5, 6 | warning style; import from `probe.ts`; loose issues exclude groups |
| `dashiboard-ui/src/components/GroupsEditor.tsx` | 6 | Confirm asks the probe; live group issues |
| `dashiboard-ui/src/completeness.ts` | 6 | `checkGroup` deleted |
| `dashiboard-ui/src/components/SelectorField.tsx` | 8 | missing chips with × |
| `dashiboard-ui/src/left-tabs/loading.tsx` | 9 | filters reset on a table change |
| `dashiboard-ui/src/session.ts` | 10 | gate state, recover, reset |
| `dashiboard-ui/src/App.tsx` | 10 | the gate, Start over |
| `dashiboard-ui/src/components/TableView.tsx` | 10 | "no table loaded" overlay |
| `dashiboard-ui/src/components/Disclosure.tsx` | 11 | summary row wraps |

---

### Task 1: A14 — a document with no cards builds and runs

**Files:**
- Modify: `Pipelines/src/group_api/dag.jl:23`
- Modify: `Pipelines/test/groups.jl` (append a testset at the end of the file)
- Modify: `DashiBoard/test/dashiboard.jl` (insert before the `# A failed run still rebuilds` comment block, ~line 415)

**Interfaces:**
- Produces: `Pipelines.Pipeline(Any[], Dict{String,Any}(), cols)` constructs; `probe-pipeline` and `evaluate-pipeline` accept `{filters, nodes: [], groups: {}}`.

- [ ] **Step 1: Write the failing Pipelines test**

Append to `Pipelines/test/groups.jl`:

```julia
@testset "a document with no cards" begin
    # A filter-only run — filter the source, run, look — and the probe of a document whose last
    # card was just removed both build a `Pipeline` with zero nodes. Measured 2026-09-16: the
    # `reduce(vcat, ...)` over zero node outputs threw "reducing over an empty collection".
    p = Pipelines.Pipeline(Any[], Dict{String, Any}(), ["TEMP", "PRES"])
    @test Pipelines.get_output_vars(p) == String[]
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=Pipelines/test Pipelines/test/runtests.jl > /tmp/claude-1000/pipelines-t1-red.log 2>&1`; read the log.
Expected: FAIL — `ArgumentError: reducing over an empty collection is not allowed`.

- [ ] **Step 3: Implement**

In `Pipelines/src/group_api/dag.jl`, replace line 23:

```julia
    # `init` admits a document with no cards. A filter-only document — filter the source, run,
    # look — and the probe of a document whose last card was just removed both arrive here with
    # `n_nodes == 0`, and `reduce` over zero outputs threw "reducing over an empty collection"
    # (measured 2026-09-16 on the Run button of a filter-only document). `c.outputs` holds one
    # `Vector{String}` per vertex, so the empty concatenation is `String[]`.
    output_vars = reduce(vcat, view(c.outputs, 1:n_nodes); init = String[])
```

- [ ] **Step 4: Run the Pipelines suite** — expected: all pass.

- [ ] **Step 5: Write the failing DashiBoard test**

Insert in `DashiBoard/test/dashiboard.jl`, inside `@testset "request"`, before the comment block that begins `# A failed run still rebuilds `selection` from `source``:

```julia
        # A14: a document with no cards. Filter-only is a legitimate run (filter, run, look), and
        # the probe of an empty document is what the UI sends when the last card is removed.
        # Placed before the failing-run block below: this run succeeds and leaves `selection`
        # equal to `source`, which that block's CSV assertion tolerates.
        body = JSON.json((; filters = [], nodes = [], groups = Dict{String, Any}()))
        resp = HTTP.post(url * "probe-pipeline", body = body)
        @test JSON.parse(resp.body)["valid"] == true
        resp = HTTP.post(url * "evaluate-pipeline", body = body)
        empty_run = JSON.parse(resp.body)
        @test empty_run["valid"] == true
        @test "TEMP" in [s["name"] for s in empty_run["summaries"]]
```

- [ ] **Step 6: Run the DashiBoard suite**

Run: `DASHIBOARD_CACHE=/tmp/dashi-test-post-smoke julia --project=DashiBoard/test DashiBoard/test/runtests.jl > /tmp/claude-1000/dashi-t1.log 2>&1`; read the log.
Expected: all pass (Step 3 already landed). If `evaluate-pipeline` of an empty document fails elsewhere (`report`, `visualize`, `graphviz` on zero nodes), fix the smallest thing in the handler with a comment naming this case, and record it in the report.

- [ ] **Step 7: Mutation-test** — remove `; init = String[]`: both new tests fail. Restore.

- [ ] **Step 8: Commit** — `A14: a document with no cards builds and runs`.

---

### Task 2: `severity` on every issue; an empty group is a definition-time error

**Files:**
- Modify: `Pipelines/src/group_api/schema.jl:178-188` (`issue_report`)
- Modify: `DashiBoard/src/handlers.jl` (`probe_pipeline` ~166–235, `evaluate_pipeline` ~240–290; new `empty_group_issues` above `probe_pipeline`)
- Modify: `DashiBoard/test/dashiboard.jl` (insert after Task 1's block)

**Interfaces:**
- Produces: every issue carries `severity`; `empty_group_issues(groups::AbstractDict)` → vector of issue named tuples with `pointer = "/groups/<name>"`, `reason = "empty"`; both pipeline routes answer `valid: false, kind: "pipeline", issues` for an empty group before building.
- Consumes: Task 1 (an empty document must still probe as valid: a document with no groups yields no issues).

- [ ] **Step 1: Write the failing tests**

Insert in `DashiBoard/test/dashiboard.jl` after Task 1's block:

```julia
        # An empty group is a document the schema accepts (`weather = []` constructs) that
        # resolves to zero columns; a card reading it used to die inside the card constructor
        # with `UndefKeywordError: keyword argument args not assigned` (measured 2026-09-16,
        # smoke check 5). The probe and the run both name the group instead.
        reads_empty = JSON.json((;
            filters = [],
            nodes = [(; id = "z", card = Dict(
                "type" => "rescale", "method" => Dict("type" => "zscore"),
                "inputs" => [Dict("groups" => "empty")], "suffix" => "z",
            ))],
            groups = Dict("empty" => []),
        ))
        for route in ("probe-pipeline", "evaluate-pipeline")
            resp = HTTP.post(url * route, body = reads_empty)
            answer = JSON.parse(resp.body)
            @test answer["valid"] == false
            @test answer["kind"] == "pipeline"
            issue = only(answer["issues"])
            @test issue["pointer"] == "/groups/empty"
            @test issue["reason"] == "empty"
            @test issue["severity"] == "error"
            @test occursin("empty", issue["message"])
            @test !occursin("UndefKeywordError", join(answer["errors"]))
        end
        # Every issue says how bad it is; a schema failure is an error.
        two_broken = JSON.json((;
            filters = [],
            nodes = [(; id = "a", card = Dict("type" => "cluster")),
                     (; id = "b", card = Dict("type" => "split"))],
            groups = Dict{String, Any}(),
        ))
        resp = HTTP.post(url * "evaluate-pipeline", body = two_broken)
        failed = JSON.parse(resp.body)
        @test failed["valid"] == false && failed["kind"] == "pipeline"
        @test [i["pointer"] for i in failed["issues"]] == ["/nodes/0/card", "/nodes/1/card"]
        @test all(i["severity"] == "error" for i in failed["issues"])
        @test !isempty(failed["errors"])
```

- [ ] **Step 2: Run to verify they fail**

Expected: `issues` empty for the empty-group routes (the run answers `kind: "execution"` with `UndefKeywordError`); `severity` key missing on the schema issues.

- [ ] **Step 3: `severity` in `issue_report`**

In `Pipelines/src/group_api/schema.jl`, in `issue_report`'s returned tuple, after `reason = issue.reason,` add:

```julia
        # A schema failure is always an error: the document cannot be built. The field exists
        # so that the same list can carry warnings — an output that overwrites a column, say —
        # and a client tells the two apart without a second list.
        severity = "error",
```

and extend the docstring of `issue_report` (above line 164) with one sentence: "`severity` is `"error"` for every schema issue; warnings are emitted elsewhere with the same shape."

- [ ] **Step 4: `empty_group_issues` in `DashiBoard/src/handlers.jl`**

Above `probe_pipeline`:

```julia
"""
    empty_group_issues(groups)

One `pipeline`-kind issue per group that names no columns.

A group with an empty selector list is a legal document — `weather = []` constructs — and it
resolves to zero columns, so a card reading it is built with no inputs and dies inside the card
constructor with `UndefKeywordError: keyword argument args not assigned` (measured 2026-09-16,
smoke check 5). That message names the implementation, not the mistake. Checked here, before the
pipeline is built, because the group API keeps no provenance from a resolved column list back to
the group that produced it: by the time construction fails, which group was empty is no longer
knowable. Reported by the probe and by the run alike, in the same shape as a schema failure, so a
form addresses the group rather than printing a sentence above the page.
"""
function empty_group_issues(groups::AbstractDict)
    return [
        (;
            pointer = "/groups/" * Pipelines.escape_pointer(String(name)),
            reason = "empty",
            severity = "error",
            found = nothing,
            allowed = nothing,
            missing = String[],
            related = String[],
            message = "group `$(name)` has no columns",
        )
            for (name, items) in pairs(groups) if items isa AbstractVector && isempty(items)
    ]
end
```

(If `Pipelines.escape_pointer` is not reachable by qualified name, use `replace(String(name), "~" => "~0", "/" => "~1")` and say so in the report.)

In `probe_pipeline`, after `groups = get(spec, "groups", Dict{String, Any}())`:

```julia
    # Before building: see `empty_group_issues` for why construction cannot report this itself.
    empty = empty_group_issues(groups)
    isempty(empty) || return json_response((;
        valid = false, kind = "pipeline", cols,
        errors = [issue.message for issue in empty], issues = empty,
    ))
```

Also add `severity = "error",` to the `unproduced_issues` tuple (after `reason = "unproduced",`) with the comment `# an error: nothing produces the column, so the document cannot run`.

In `evaluate_pipeline`, inside the first `try`, after `groups = get(spec, "groups", Dict{String, Any}())` and before `Pipelines.Pipeline(...)`:

```julia
        empty = empty_group_issues(groups)
        isempty(empty) || return json_response((;
            valid = false, kind = "pipeline",
            errors = [issue.message for issue in empty], issues = empty,
        ))
```

- [ ] **Step 5: Run the DashiBoard suite** — expected: all pass, Task 1's block included.

- [ ] **Step 6: Mutation-test** — make `empty_group_issues` return `[]`: the empty-group loop fails (run answers `execution`). Restore. Remove `severity = "error",` from `issue_report`: the `two_broken` severity assertion fails. Restore.

- [ ] **Step 7: Commit** — `issues carry severity; an empty group is reported before anything is built`.

---

### Task 3: A13 — overwriting an existing column is a warning

**Files:**
- Modify: `DashiBoard/src/handlers.jl` (new `overwrite_warnings` above `probe_pipeline`; wire into `probe_pipeline`'s `issues`)
- Modify: `DashiBoard/test/dashiboard.jl` (insert after Task 2's block)

**Interfaces:**
- Consumes: `severity` (Task 2); `Pipelines.get_node_outputs(node)` (exists, used by the probe).
- Produces: probe issues with `reason = "overwrites"`, `severity = "warning"`, `pointer = "/nodes/<i>/card"`; `valid` unaffected.

- [ ] **Step 1: Write the failing test**

```julia
        # A13: two cards emitting the same column name. The second silently replaced the first's
        # output (and a source column would be replaced the same way — `rescale TEMP suffix =
        # "rescaled"` over a source with `TEMP_rescaled`, measured 2026-09-13 and on 1M rows
        # 2026-09-16). A warning, not a rejection: overwriting can be meant.
        same_name = JSON.json((;
            filters = [],
            nodes = [
                (; id = "one", card = Dict("type" => "rescale", "method" => Dict("type" => "zscore"),
                    "inputs" => [Dict("cols" => "TEMP")], "suffix" => "z")),
                (; id = "two", card = Dict("type" => "rescale", "method" => Dict("type" => "minmax"),
                    "inputs" => [Dict("cols" => "TEMP")], "suffix" => "z")),
            ],
            groups = Dict{String, Any}(),
        ))
        resp = HTTP.post(url * "probe-pipeline", body = same_name)
        probed = JSON.parse(resp.body)
        @test probed["valid"] == true
        warning = only(i for i in probed["issues"] if i["reason"] == "overwrites")
        @test warning["severity"] == "warning"
        @test warning["pointer"] == "/nodes/1/card"
        @test occursin("TEMP_z", warning["message"])
        resp = HTTP.post(url * "evaluate-pipeline", body = same_name)
        @test JSON.parse(resp.body)["valid"] == true
```

- [ ] **Step 2: Run to verify it fails** — expected: `only` throws (no `overwrites` issue).

- [ ] **Step 3: Implement**

Above `probe_pipeline`:

```julia
"""
    overwrite_warnings(pipeline, cols)

A warning per node whose outputs replace a column that already exists — in the source, or emitted
by an earlier node.

`rescale TEMP suffix = "rescaled"` against a source that already holds `TEMP_rescaled` is accepted
at every layer and silently replaces the column (A13, measured 2026-09-13 and on 1M rows
2026-09-16). Overwriting can be meant, so `severity = "warning"`: `valid` stays true and the run is
allowed; the form shows it on the card. Nodes are walked in document order, so the later of two
cards emitting the same name is the one warned, and a name is compared against everything that
exists *before* the node runs.
"""
function overwrite_warnings(pipeline, cols::AbstractVector)
    seen = Set{String}(cols)
    warnings = []
    for (i, node) in enumerate(pipeline.nodes)
        outputs = Pipelines.get_node_outputs(node)
        clashing = [name for name in outputs if name in seen]
        if !isempty(clashing)
            push!(warnings, (;
                pointer = "/nodes/$(i - 1)/card",
                reason = "overwrites",
                severity = "warning",
                found = nothing,
                allowed = nothing,
                missing = String[],
                related = String[],
                message = join(("`$(name)` already exists and will be replaced" for name in clashing), "; "),
            ))
        end
        union!(seen, outputs)
    end
    return warnings
end
```

In `probe_pipeline`'s final `json_response`, replace `issues = unproduced_issues,` with:

```julia
        # Errors first, then warnings: a client reading the list top-down sees what blocks the
        # run before what merely deserves a look.
        issues = vcat(unproduced_issues, overwrite_warnings(pipeline, cols)),
```

- [ ] **Step 4: Run the DashiBoard suite** — all pass.
- [ ] **Step 5: Mutation-test** — `return []` from `overwrite_warnings`: the test fails. Restore.
- [ ] **Step 6: Commit** — `A13: warn when a card's output replaces a column that exists`.

---

### Task 4: A12 — non-finite floats become `null`, in the summaries and in the rows

**Files:**
- Modify: `DashiBoard/src/middleware.jl:116-119` (`json_response`)
- Modify: `DashiBoard/src/handlers.jl` (`fetch_data`, ~line 308–335)
- Modify: `DashiBoard/test/dashiboard.jl` (a unit test near the top, beside the `root_causes` testset; a live test after Task 3's block)

**Interfaces:**
- Produces: `json_response` never throws on `NaN`/`Inf`; `fetch-data` bodies contain `null` where a float was non-finite.

- [ ] **Step 1: Write the failing tests**

Beside `@testset "root_causes"` (top of the file):

```julia
@testset "json_response and non-finite floats" begin
    # A12: `JSON.json` refuses NaN and Inf, so a run whose z-score of a constant column was NaN
    # on every row was reported as an execution failure (measured on `constant = 42`, 2026-09-13
    # and 2026-09-16). `null` is what every JSON client reads as "no value".
    resp = DashiBoard.json_response((; a = [1.0, NaN, Inf, -Inf], b = Dict("x" => NaN)))
    body = String(resp.body)
    @test !occursin("NaN", body) && !occursin("Infinity", body)
    @test JSON.parse(body)["a"] == [1.0, nothing, nothing, nothing]
    @test JSON.parse(body)["b"]["x"] === nothing
end
```

After Task 3's block, in the live testset:

```julia
        # The rows take a different path — DuckDB writes the page as JSON itself, and its writer
        # emits bare `NaN`/`Infinity`, which a browser's JSON.parse rejects (measured 2026-09-16).
        # Julia's parser accepts those tokens, so this asserts on the text.
        DBInterface.execute(DashiBoard.REPOSITORY[],
            "CREATE OR REPLACE TABLE selection AS SELECT 'nan'::DOUBLE AS bad, 2.5 AS good, 'x' AS s")
        body = JSON.json((; offset = 0, limit = 10, filterModel = Dict(), sortModel = [], processed = true))
        resp = HTTP.post(url * "fetch-data", body = body)
        page = String(resp.body)
        @test !occursin("NaN", page) && !occursin("Infinity", page)
        @test JSON.parse(page)["values"][1]["bad"] === nothing
        @test JSON.parse(page)["values"][1]["good"] == 2.5
```

(`DBInterface` is already imported by the test file; if not, add `using DBInterface`.)

- [ ] **Step 2: Run to verify they fail** — expected: `ArgumentError: NaN not allowed`; `occursin("NaN", page)` true.

- [ ] **Step 3: `json_response`**

Replace the function in `DashiBoard/src/middleware.jl`:

```julia
"""
    json_response(d; omit_null = false)

A 200 with `d` as JSON and the CORS headers.

Non-finite floats are written as `null`. `JSON.json` refuses `NaN` and `Inf` outright, so a run
whose z-score of a zero-variance column was `NaN` on every row was reported to the client as an
execution failure (A12, measured on `constant = 42`, 2026-09-13 and 2026-09-16) — the pipeline
had succeeded; only the response could not be written. `allownan = true` alone is not the fix:
the tokens it writes are not JSON and the browser's parser rejects them. `null` is what every
JSON client already reads as "no value", and it is what the rows path (`fetch_data`) produces too.
"""
function json_response(d; omit_null::Bool = false)
    headers = vcat(CORS_RES_HEADERS, ["Content-Type" => "application/json"])
    body = JSON.json(d; omit_null, allownan = true, nan = "null", inf = "null", ninf = "null")
    return HTTP.Response(200, headers = headers, body = body)
end
```

- [ ] **Step 4: `fetch_data`**

In `DashiBoard/src/handlers.jl`, `fetch_data`, replace the query line `q = From(table) |> Order(by = sorter_nodes) |> Limit(; limit, offset)` with a projection that casts non-finite floats to NULL, and add the helper above the function:

```julia
"""
    finite_projection(repository, table)

`Select` every column of `table`, with each floating-point column replaced by
`CASE WHEN isfinite(col) THEN col END`.

DuckDB's JSON writer emits bare `NaN` and `Infinity`, which are not JSON: a page of a z-scored
constant column was unreadable to the browser (A12, measured 2026-09-16). The cast happens in
SQL so the page is written once and never post-processed as text. Column types come from
`information_schema`, which is a catalogue lookup — not a pass over the table.
"""
function finite_projection(repository, table::AbstractString)
    types = DBInterface.execute(
        DataFrame, repository,
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '$(table)'",
    )
    floaty = Set(("DOUBLE", "FLOAT", "REAL"))
    return Select((
        name => (type in floaty ? Fun.case(Fun.isfinite(Get(name)), Get(name)) : Get(name))
            for (name, type) in zip(types.column_name, types.data_type)
    )...)
end
```

and in `fetch_data`:

```julia
        q = From(table) |> finite_projection(REPOSITORY[], table) |>
            Order(by = sorter_nodes) |> Limit(; limit, offset)
```

`DataFrame` must be in scope in `handlers.jl` (check the module's `using`; `DataFrames` is a DashiBoard dependency if the tests use it — otherwise read the result with `DBInterface.execute(...)` and iterate rows). If FunSQL's `Fun.case` renders differently from `CASE WHEN … THEN … END`, use the form that does and say so in the report; the test is the arbiter.

- [ ] **Step 5: Run the DashiBoard suite** — all pass.
- [ ] **Step 6: Mutation-test** — remove `nan = "null"` (keep `allownan`): the unit test fails on `occursin("NaN")`. Restore. Replace `finite_projection` with `Select(Get.*)`-equivalent (no cast): the live test fails. Restore.
- [ ] **Step 7: Commit** — `A12: non-finite floats are null in every response, summaries and rows alike`.

---

### Task 5: Run failures land on the cards; warnings render as warnings

**Files:**
- Create: `dashiboard-ui/src/probe.ts`
- Modify: `dashiboard-ui/src/stores.ts` (`ProbeIssue`, new `reportRunIssues`, new `issuesForGroup`)
- Modify: `dashiboard-ui/src/left-tabs/results.tsx` (`RunResult`, `run()`, the failure block)
- Modify: `dashiboard-ui/src/left-tabs/processing.tsx` (import from `probe.ts`; `issueFindings`; the `schemaIssuesForNode` render)
- Test: `dashiboard-ui/src/left-tabs/results.test.tsx`, `dashiboard-ui/src/left-tabs/processing.test.tsx`

**Interfaces:**
- Produces: `askProbe(document: CardsStore): Promise<ProbeStore>` and `usableProbe(result: unknown): ProbeStore` from `src/probe.ts`; `reportRunIssues(issues: ProbeIssue[]): void`; `issuesForGroup(issues: ProbeIssue[], name: string): ProbeIssue[]`; `ProbeIssue.severity?: "error" | "warning"`.
- Consumes: Tasks 2–3's response shapes.

- [ ] **Step 1: Write the failing tests**

Append to `results.test.tsx` (it already mocks `postRequest` and imports `Results`; reuse its helpers):

```tsx
describe('a run that failed to build', () => {
  it('puts the server\'s issues on the cards and names the count', async () => {
    // Check 12 by hand: two incomplete cards, Run → the pane showed JSONSchema.jl's raw text
    // while Confirm on the same card showed two field pointers. Same fault, one rendering.
    importCards({ nodes: [{ id: 'a', card: { type: 'cluster' } }, { id: 'b', card: { type: 'split' } }], groups: {} });
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'evaluate-pipeline'
        ? { valid: false, kind: 'pipeline', errors: ['2 schema validation errors: …'],
            issues: [
              { pointer: '/nodes/0/card', reason: 'required', severity: 'error', found: null, allowed: null, missing: ['method', 'inputs'], related: ['/nodes/0/card/method', '/nodes/0/card/inputs'], message: 'x' },
              { pointer: '/nodes/1/card', reason: 'required', severity: 'error', found: null, allowed: null, missing: ['method'], related: ['/nodes/1/card/method'], message: 'y' },
            ] }
        : []));
    const { container, getByText } = render(() => <Results />);
    fireEvent.click(getByText(/run pipeline/i));
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(container.querySelector('[data-run-error]')!.textContent).toMatch(/2 cards need attention/);
    const { PROBE_STORE } = await import('../stores');
    expect(PROBE_STORE[0].issues.map((i) => i.pointer)).toEqual(['/nodes/0/card', '/nodes/1/card']);
  });
});
```

Append to `processing.test.tsx`:

```tsx
describe('a warning from the probe', () => {
  it('renders in the warning style and does not block Confirm', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? { ...CLEAN_PROBE, issues: [{ pointer: '/nodes/0/card', reason: 'overwrites', severity: 'warning', found: null, allowed: null, missing: [], related: [], message: '`TEMP_z` already exists and will be replaced' }] }
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );
    const { container, getAllByText } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(container.querySelector('[data-issue-severity="warning"]')!.className).toMatch(/warning/);
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
  });
});
```

(`fireEvent` from `@solidjs/testing-library`; `CLEAN_PROBE`, `payload`, `postRequest` exist at the top of the file.)

- [ ] **Step 2: Run to verify they fail** — expected: the pane shows the prose only, `PROBE_STORE.issues` stays `[]`; no `[data-issue-severity]` element.

- [ ] **Step 3: `src/probe.ts`**

Move `usableProbe` and `askProbe` out of `processing.tsx` verbatim (they read nothing from the component) into:

```ts
import { postRequest } from "./requests";
import { emptyProbe, type CardsStore, type ProbeStore } from "./stores";

// One place to ask `POST /probe-pipeline`. The card Confirm, the continuous probe and — since the
// empty-group check moved to the server — the group Confirm all ask the same question.

/** Coerce a probe reply into something the store can hold, whatever the server sent. */
export const usableProbe = (result: unknown): ProbeStore => {
  const reported = result as ProbeStore | null;
  const ok = reported !== null && typeof reported === "object" &&
    Array.isArray(reported.nodes) && Array.isArray(reported.errors);
  return ok ? { ...reported, issues: Array.isArray(reported.issues) ? reported.issues : [] } : emptyProbe();
};

/** Ask once and get the shape back. */
export async function askProbe(document: CardsStore): Promise<ProbeStore> {
  return usableProbe(await postRequest("probe-pipeline", document, null));
}
```

In `processing.tsx` delete the two local definitions and `import { askProbe } from "../probe";`.

- [ ] **Step 4: `stores.ts`**

In `ProbeIssue` add, after `reason: string;`:

```ts
  /** How bad: an error blocks the run; a warning (a column about to be overwritten) does not. Absent from an older server means error. */
  severity?: "error" | "warning";
```

After `issuesForNode`, add:

```ts
/** The issues addressing one group — `/groups/<name>` and anything below it. */
export function issuesForGroup(issues: ProbeIssue[], name: string): ProbeIssue[] {
  const want = ["", "groups", name.replace(/~/g, "~0").replace(/\//g, "~1")];
  return issues.filter((issue) => {
    const parts = issue.pointer.split("/");
    return want.every((segment, i) => parts[i] === segment);
  });
}

/**
 * A run that failed to build says where, in the probe's shape — so the cards show it as they
 * show a probe finding. Written into `PROBE_STORE` rather than kept by the results pane: the
 * cards already read one place, and the next edit's probe replaces this as it replaces any result.
 */
export function reportRunIssues(issues: ProbeIssue[]) {
  const [, setProbe] = PROBE_STORE;
  setProbe((draft) => {
    draft.valid = false;
    draft.issues = issues;
  });
}
```

- [ ] **Step 5: `results.tsx`**

Add `issues?: ProbeIssue[];` to `RunResult` (import the type from `../stores`). In `run()`, in the `answer.valid === false` branch, before `setFailure`:

```ts
        const issues = Array.isArray(answer.issues) ? answer.issues : [];
        if (issues.length > 0) reportRunIssues(issues);
        const cards = new Set(issues.map((i) => i.pointer.split("/")[2]).filter(Boolean)).size;
        setFailure({
          kind: answer.kind,
          // Pointed issues are on the cards; the prose stays as the fallback for faults that
          // carry no pointer — a cycle, a filter's SQL error.
          errors: [
            ...(cards > 0 ? [`${cards} card${cards === 1 ? "" : "s"} need attention — see the marks on them.`] : []),
            ...(answer.errors?.length ? answer.errors : ["The run failed, without saying why."]),
          ],
        });
```

(and remove the old `setFailure({...})` in that branch).

- [ ] **Step 6: `processing.tsx` — warnings**

In `issueFindings`, first branch:

```ts
      if (issue.severity === "warning") {
        return [{ message: issue.message, pointer: issue.pointer, severity: "warning" as const }];
      }
```

and add `severity?: "error" | "warning";` to `Incompleteness` in `completeness.ts`. In the `schemaIssuesForNode` `<For>` render (the `<p class="mb-2 rounded-sm border border-destructive/30 …">`), make the class depend on severity and stamp it:

```tsx
                <p
                  data-issue-severity={issue.severity ?? "error"}
                  class={[
                    "mb-2 rounded-sm border p-2 text-control-xs",
                    issue.severity === "warning"
                      ? "border-warning/40 bg-warning/10 text-foreground"
                      : "border-destructive/30 bg-destructive/10 text-destructive",
                  ]}
                >
```

`confirmNode`'s `graphFindings` must not count a warning as unfinished: filter `issue.severity !== "warning"` before `issueFindings` there, and render the warning through the probe path (it already does, live).

- [ ] **Step 7: Run the four UI checks** — all pass; 0 `STRICT_READ_UNTRACKED`.
- [ ] **Step 8: Mutation-test** — remove the `reportRunIssues(issues)` call: the results test fails on `PROBE_STORE.issues`. Restore. Make the class always destructive: the processing test's `className` match fails. Restore.
- [ ] **Step 9: Commit** — `Run failures land on the cards; warnings render as warnings`.

---

### Task 6: The groups editor asks the probe; `checkGroup` goes

**Files:**
- Modify: `dashiboard-ui/src/components/GroupsEditor.tsx` (Confirm handler ~line 118–130; the findings `<For>` ~140–146)
- Modify: `dashiboard-ui/src/completeness.ts` (delete `checkGroup` and its docstring; update the header comment's last paragraph)
- Modify: `dashiboard-ui/src/completeness.test.ts` (delete the `checkGroup` describe)
- Modify: `dashiboard-ui/src/left-tabs/processing.tsx` (`looseIssues` excludes `/groups/` pointers)
- Test: `dashiboard-ui/src/components/GroupsEditor.test.tsx`

**Interfaces:**
- Consumes: `askProbe` (Task 5), `issuesForGroup` (Task 5), the server's `/groups/<name>` issue (Task 2).

- [ ] **Step 1: Write the failing test**

Append to `GroupsEditor.test.tsx` (it renders `GroupsEditor` with `defs` from the fixture; add a `postRequest` mock at the top of the file in the same shape as `processing.test.tsx` if it has none):

```tsx
  it('shows the server\'s finding for an empty group after Confirm', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'probe-pipeline'
        ? { valid: false, kind: 'pipeline', cols: [], nodes: [], errors: ['group `g` has no columns'],
            issues: [{ pointer: '/groups/g', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `g` has no columns' }] }
        : []));
    importCards({ nodes: [], groups: { g: [] } });
    const { container, getAllByText } = render(() => <GroupsEditor defs={defs} />);
    fireEvent.click(getAllByText('Confirm')[0]);
    await waitFor(() => expect(container.textContent).toMatch(/has no columns/));
    expect(postRequest.mock.calls.some((c) => c[0] === 'probe-pipeline')).toBe(true);
  });
```

- [ ] **Step 2: Run to verify it fails** — the text shown is `checkGroup`'s "Add at least one column…" and no probe call is made.

- [ ] **Step 3: Implement**

`GroupsEditor.tsx`: replace the Confirm handler body with

```tsx
                          void (async () => {
                            // The server's answer, not ours: an empty group is reported by the
                            // probe since the 2026-09-16 fixes (`empty_group_issues`), so the
                            // one rule that used to live here (`checkGroup`) is gone.
                            const answer = await askProbe(JSON.parse(JSON.stringify(state)) as CardsStore);
                            const found = issuesForGroup(answer.issues, name).map((issue) => ({
                              message: issue.message, pointer: issue.pointer,
                            }));
                            setUnfinished({ ...unfinished(), [name]: found });
                            if (found.length === 0) confirmDefinition(`group:${name}`, state.groups[name]);
                          })();
```

with `import { askProbe } from "../probe";` and `issuesForGroup`, `CardsStore` from `../stores`; drop the `checkGroup` import. Rewrite the comment above the Confirm button (the "Unwired, deliberately…" block) to say what it now does. Also render the continuous probe's group issues live: below the `unfinished` `<For>`, add

```tsx
                <For each={issuesForGroup(probe.issues, name)}>
                  {(issue) => (
                    <p class="rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground">
                      {issue.message}
                    </p>
                  )}
                </For>
```

with `const [probe] = PROBE_STORE;` at the top of the component. `processing.tsx` `looseIssues`: also exclude `issue.pointer.startsWith("/groups/")` — the groups editor shows those.

`completeness.ts`: delete `checkGroup` and its docstring; in the header comment replace the last paragraph with: "`checkNode` is what is left. `checkGroup` went on 2026-09-16 when the probe learned to report an empty group itself (`empty_group_issues`)." `completeness.test.ts`: delete the `checkGroup` describe and its import.

- [ ] **Step 4: Run the four UI checks** — all pass; `grep -rn checkGroup src` returns nothing.
- [ ] **Step 5: Mutation-test** — make the handler skip `askProbe` and set `found = []`: the test fails. Restore.
- [ ] **Step 6: Commit** — `groups: Confirm asks the probe; checkGroup deleted`.

---

### Task 7: Cascade references when a group or node is removed or renamed

**Files:**
- Modify: `dashiboard-ui/src/stores.ts` (`removeGroup`, `renameGroup`, `setNodeId`, `removeNode`; new `forEachSelector`)
- Test: `dashiboard-ui/src/stores.test.ts`

**Interfaces:**
- Produces: `removeGroup(name)` / `removeNode(index)` also drop `{groups: name}` / `{nodes: id}` items and `through` entries naming the id, everywhere; `renameGroup(from, to)` / `setNodeId(index, id)` rewrite them.

- [ ] **Step 1: Write the failing tests**

Append to `stores.test.ts`:

```ts
describe('references follow the thing they name', () => {
  // Check 6 by hand: deleting the group `empty` left `groups:empty` on the card, with no way to
  // remove it — the picker only offers switches for values in the vocabulary.
  const doc = () => ({
    nodes: [
      { id: 'r', card: { type: 'rescale', inputs: [{ groups: 'g' }, { cols: 'TEMP' }], group_by: [{ groups: 'g' }] } },
      { id: 's', card: { type: 'rescale', inputs: [{ nodes: 'r' }, { cols: 'PRES', through: ['r'] }] } },
    ],
    groups: { g: [{ cols: ['TEMP'] }], h: [{ groups: 'g' }, { cols: 'PRES' }] },
  });
  it('removeGroup drops every item naming the group', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.removeGroup('g'); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ cols: 'TEMP' }]);
    expect(out.nodes[0].card.group_by).toEqual([]);
    expect(out.groups.h).toEqual([{ cols: 'PRES' }]);
  });
  it('renameGroup rewrites them', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.renameGroup('g', 'wind'); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ groups: 'wind' }, { cols: 'TEMP' }]);
    expect(out.groups.h[0]).toEqual({ groups: 'wind' });
  });
  it('removeNode drops nodes: items and through entries', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.removeNode(0); await flush();
    const out = s.exportCards();
    expect(out.nodes[0].card.inputs).toEqual([{ cols: 'PRES' }]);   // `through: ['r']` gone with r
  });
  it('setNodeId rewrites nodes: items and through entries', async () => {
    const s = await import('./stores');
    s.importCards(doc()); s.setNodeId(0, 'rescaled'); await flush();
    const out = s.exportCards();
    expect(out.nodes[1].card.inputs).toEqual([{ nodes: 'rescaled' }, { cols: 'PRES', through: ['rescaled'] }]);
  });
});
```

- [ ] **Step 2: Run to verify they fail** — the references are untouched.

- [ ] **Step 3: Implement**

In `stores.ts`, above `removeGroup`:

```ts
/**
 * Every selector item in the document, with a callback that returns the item to keep — or
 * `null` to drop it.
 *
 * A selector is *structural*: any array whose objects carry `cols` / `groups` / `nodes` /
 * `through`. Walked that way rather than by asking the IR which fields are selectors, so a field
 * this UI has never heard of is covered too. Items left with no value are dropped, and a group's
 * own selector list is walked like a card's — groups may name groups.
 */
function forEachSelector(draft: CardsStore, edit: (item: Selector) => Selector | null) {
  const isSelector = (v: unknown): v is Selector[] =>
    Array.isArray(v) && v.every((x) => x && typeof x === "object" &&
      ["cols", "groups", "nodes", "through"].some((k) => k in (x as object)));
  const walk = (holder: Record<string, unknown>) => {
    for (const [key, value] of Object.entries(holder)) {
      if (isSelector(value)) {
        holder[key] = value.map(edit).filter((item): item is Selector => item !== null);
      } else if (value && typeof value === "object" && !Array.isArray(value)) {
        walk(value as Record<string, unknown>);
      }
    }
  };
  for (const node of draft.nodes) walk(node.card as Record<string, unknown>);
  for (const name of Object.keys(draft.groups)) {
    draft.groups[name] = draft.groups[name].map(edit).filter((item): item is Selector => item !== null);
  }
}

/** `{kind: value}` with `name` taken out of the kind's one-or-many value; `null` when nothing is left. */
function dropName(item: Selector, kind: "groups" | "nodes", name: string): Selector | null {
  const out: Selector = { ...item };
  const value = out[kind];
  const rest = (Array.isArray(value) ? value : value === undefined ? [] : [value]).filter((v) => v !== name);
  if (Array.isArray(value) || value === undefined) { if (rest.length === 0) delete out[kind]; else out[kind] = rest; }
  else if (value === name) delete out[kind];
  if (Array.isArray(out.through)) {
    out.through = out.through.filter((v) => v !== name);
    if (out.through.length === 0) delete out.through;
  }
  return "cols" in out || "groups" in out || "nodes" in out ? out : null;
}

function renameIn(item: Selector, kind: "groups" | "nodes", from: string, to: string): Selector {
  const out: Selector = { ...item };
  const value = out[kind];
  if (Array.isArray(value)) out[kind] = value.map((v) => (v === from ? to : v));
  else if (value === from) out[kind] = to;
  if (Array.isArray(out.through)) out.through = out.through.map((v) => (v === from ? to : v));
  return out;
}
```

Then: `removeGroup` → inside `setCards`, after `delete draft.groups[name]`, `forEachSelector(draft, (item) => dropName(item, "groups", name));`. `renameGroup` → after rebuilding `draft.groups`, `forEachSelector(draft, (item) => renameIn(item, "groups", from, to));`. `removeNode` → capture `const id = draft.nodes[nodeIndex]?.id;` before the splice, then `if (id) forEachSelector(draft, (item) => dropName(item, "nodes", id));`. `setNodeId` → capture `const from = draft.nodes[nodeIndex].id;` then set, then `if (from && from !== id) forEachSelector(draft, (item) => renameIn(item, "nodes", from, id));`. Check the `Selector` type (stores.ts ~line 70) admits `through`; widen it if not.

- [ ] **Step 4: Run the four UI checks** — all pass (existing `GroupsEditor`/`processing` tests included).
- [ ] **Step 5: Mutation-test** — remove the `forEachSelector` call from `removeGroup`: the first test fails. Restore.
- [ ] **Step 6: Commit** — `stores: references follow the group or node they name`.

---

### Task 8: A chip the vocabulary cannot name is marked and removable

**Files:**
- Modify: `dashiboard-ui/src/components/SelectorField.tsx` (the chip `<li>` ~line 175–210)
- Test: `dashiboard-ui/src/components/SelectorField.test.tsx`

**Interfaces:** none new. `switchOff(kind, value)` (exists) is the removal.

- [ ] **Step 1: Write the failing test**

```tsx
  it('marks a value the vocabulary cannot name, and lets it be removed', async () => {
    // Check 11 by hand: after loading a table without TEMP, a card's `{cols: "TEMP"}` had no
    // switch to turn it off — the picker lists the vocabulary, and the value was not in it.
    const onChange = vi.fn();
    const { container } = render(() => (
      <SelectorField itemNode={itemNode} defs={defs} label="inputs"
        value={[{ cols: 'GONE' }, { cols: 'TEMP' }]} onChange={onChange} />
    ));
    const chip = container.querySelector('[data-chip="cols:GONE"]')!;
    expect(chip.getAttribute('data-missing')).toBe('true');
    expect(container.querySelector('[data-chip="cols:TEMP"]')!.getAttribute('data-missing')).toBeNull();
    fireEvent.click(chip.querySelector('[data-remove]')!);
    await flush();
    expect(onChange).toHaveBeenCalledWith([{ cols: 'TEMP' }]);
  });
```

(`vi` import if absent; `defs`/`itemNode` are the file's fixtures — `TEMP` is in `defs.col.enum`, `GONE` is not.)

- [ ] **Step 2: Run to verify it fails** — `data-missing` absent; no `[data-remove]`.

- [ ] **Step 3: Implement**

In the chip's `<li>`: compute `const missing = () => !optionsOf(r.kind).includes(r.value);` and add `data-missing={missing() ? "true" : undefined}`, `title={missing() ? `${r.value} is not in the loaded table — remove it, or load a table that has it` : undefined}`, and a class branch `missing() ? "border-destructive/50 bg-destructive/10 text-destructive line-through" : "border-border bg-background"`. Inside the chip's button `<span class="flex">`, before the arrows:

```tsx
                    <Show when={missing()}>
                      <button
                        type="button"
                        data-remove
                        aria-label={`remove ${label()}`}
                        onClick={() => switchOff(r.kind, r.value)}
                        class="grid h-4 w-4 place-items-center rounded-sm text-destructive hover:bg-destructive/20"
                      >
                        ×
                      </button>
                    </Show>
```

Add a comment above the `<ul>`: "A value the picker cannot offer a switch for — a column the loaded table lacks, a reference in an imported document — still has to be removable here; otherwise the only way out is to rebuild the card (measured 2026-09-16)."

- [ ] **Step 4: Run the four UI checks** — all pass.
- [ ] **Step 5: Mutation-test** — make `missing` always `false`: the test fails on `data-missing`. Restore.
- [ ] **Step 6: Commit** — `SelectorField: a value the vocabulary cannot name is marked and removable`.

---

### Task 9: Filters reset when the loaded columns change

**Files:**
- Modify: `dashiboard-ui/src/left-tabs/loading.tsx` (`loadData`)
- Test: `dashiboard-ui/src/left-tabs/loading.test.tsx`

**Interfaces:** consumes `FILTERS_STORE` (exists).

- [ ] **Step 1: Write the failing test**

```tsx
  it('clears the filters when the new table has different columns, and keeps them otherwise', async () => {
    // Check 11 by hand: a list filter on `cbwd` survived loading a table with no `cbwd`, and the
    // run failed on it. Same names (stress.csv → stress.parquet) must keep the filters.
    const { FILTERS_STORE, LOADER_STORE } = await import('../stores');
    const { Interval } = await import('../stores');
    LOADER_STORE[1](reconcile([num('TEMP'), num('cbwd')]));
    FILTERS_STORE[1]((d) => { d.numerical.TEMP = new Interval(0, 1); });
    await flush();
    // same names → kept
    serveLoad([num('TEMP'), num('cbwd')]);
    const { getByText } = render(() => <Loader />);
    pick(['a.parquet']); fireEvent.click(getByText('Load'));
    await waitFor(() => expect(FILTERS_STORE[0].numerical.TEMP).toBeInstanceOf(Interval));
    // different names → reset
    serveLoad([num('No'), num('PRES')]);
    fireEvent.click(getByText('Load'));
    await waitFor(() => expect(Object.keys(FILTERS_STORE[0].numerical)).toEqual([]));
  });
```

Use the file's existing helpers for serving `load-files` and picking a file (`serveLoad`, `pick` stand for whatever it has — read the file; `num(name)` builds a numerical summary as in `rerun.test.tsx`).

- [ ] **Step 2: Run to verify it fails** — the `TEMP` filter survives the second load.

- [ ] **Step 3: Implement**

In `loadData`'s `.then`:

```ts
      .then((summaries: LoaderStore) => {
        const next = summaries ?? [];
        // Filters are authored against one table's columns. A table with different columns
        // makes them meaningless — a list filter on `cbwd` over a table with no `cbwd` failed
        // the run (measured 2026-09-16) — so a changed column set clears them; the same names
        // (the CSV and the parquet of one dataset) keep them.
        const before = state.map((s) => s.name).sort().join(" ");
        const after = next.map((s) => s.name).sort().join(" ");
        if (before !== after) setFilters(reconcile({ numerical: {}, categorical: {} }));
        setState(reconcile(next));
      })
```

with `const [, setFilters] = FILTERS_STORE;` and the import.

- [ ] **Step 4: Run the four UI checks** — all pass.
- [ ] **Step 5: Mutation-test** — drop the `if`: the "kept" assertion fails. Restore.
- [ ] **Step 6: Commit** — `loading: filters reset when the columns change`.

---

### Task 10: Session gate and Start over

**Files:**
- Create: `dashiboard-ui/src/session.ts`, `dashiboard-ui/src/session.test.ts`
- Modify: `dashiboard-ui/src/App.tsx` (gate above the outlet; Start over in the nav)
- Modify: `dashiboard-ui/src/components/TableView.tsx` (`overlayNoRowsTemplate`; `failCallback` shows it)
- Test: `dashiboard-ui/src/App.test.tsx` (new)

**Interfaces:**
- Produces: `hasPreviousSession(): boolean`, `sessionSummary(): { columns: number; groups: number; cards: number }`, `recoverSession(): void`, `resetSession(): void`.

- [ ] **Step 1: Write the failing tests**

`session.test.ts`:

```ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { flush, reconcile } from 'solid-js';

beforeEach(() => sessionStorage.clear());

describe('session', () => {
  it('has no previous session when the document is empty', async () => {
    const { hasPreviousSession } = await import('./session');
    const { importCards, emptyCards, LOADER_STORE } = await import('./stores');
    importCards(emptyCards()); LOADER_STORE[1](reconcile([])); await flush();
    expect(hasPreviousSession()).toBe(false);
  });
  it('has one when something was restored, until it is answered', async () => {
    const { hasPreviousSession, recoverSession, sessionSummary } = await import('./session');
    const { importCards } = await import('./stores');
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: { g: [] } }); await flush();
    expect(hasPreviousSession()).toBe(true);
    expect(sessionSummary()).toEqual({ columns: 0, groups: 1, cards: 1 });
    recoverSession();
    expect(hasPreviousSession()).toBe(false);
    expect(sessionStorage.getItem('dashi.gate')).toBe('answered');
  });
  it('resetSession removes exactly the dashi.* keys and reloads', async () => {
    const { resetSession } = await import('./session');
    sessionStorage.setItem('dashi.cards', '{}'); sessionStorage.setItem('dashi.tab', '"process"');
    sessionStorage.setItem('other', '1');
    const reload = vi.fn();
    resetSession(reload);
    expect(sessionStorage.getItem('dashi.cards')).toBeNull();
    expect(sessionStorage.getItem('dashi.tab')).toBeNull();
    expect(sessionStorage.getItem('other')).toBe('1');
    expect(reload).toHaveBeenCalledTimes(1);
  });
});
```

`App.test.tsx` (render `App` with a memory router as `routes/index.test.tsx` does — read `renderHome` there and mirror it for `App`; the `../requests` mock as in the other tests):

```tsx
  it('gates a restored session and lets Recover dismiss it', async () => {
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} }); await flush();
    const { container, getByText } = renderApp('/');
    await waitFor(() => expect(container.querySelector('[data-session-gate]')).not.toBeNull());
    expect(container.textContent).toMatch(/1 card/);
    fireEvent.click(getByText('Recover'));
    await flush();
    expect(container.querySelector('[data-session-gate]')).toBeNull();
  });
  it('does not gate an empty document', async () => {
    importCards(emptyCards()); await flush();
    const { container } = renderApp('/');
    await waitFor(() => expect(container.querySelector('nav')).not.toBeNull());
    expect(container.querySelector('[data-session-gate]')).toBeNull();
  });
  it('Start over asks before clearing', async () => {
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} }); await flush();
    recoverSession();
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { getByText } = renderApp('/');
    await waitFor(() => getByText('Start over'));
    fireEvent.click(getByText('Start over'));
    expect(confirm).toHaveBeenCalled();
    expect(sessionStorage.getItem('dashi.cards')).not.toBeNull();   // declined → untouched
    confirm.mockRestore();
  });
```

- [ ] **Step 2: Run to verify they fail** — `./session` does not exist; no `[data-session-gate]`, no "Start over".

- [ ] **Step 3: `session.ts`**

```ts
import { createSignal } from "solid-js";
import { CARDS_STORE, LOADER_STORE } from "./stores";

// The stores restore themselves from `sessionStorage` at module load (persist.ts). That is what
// brought a whole document back after a server restart on 2026-09-16 — right after an accident,
// too much when a fresh start was wanted, and in both cases silent. This makes the choice
// explicit: a gate once per tab when something was restored, and Start over at any time.
//
// `sessionStorage` is per tab and survives reloads, so "a previous session" can only mean this
// tab reloaded; a new tab has no storage and no gate.

const GATE = "dashi.gate";
const [answered, setAnswered] = createSignal(read());

function read(): boolean {
  try { return sessionStorage.getItem(GATE) === "answered"; } catch { return true; }
}

/** How much came back — for the gate to say what it is offering. */
export function sessionSummary() {
  const [loader] = LOADER_STORE;
  const [cards] = CARDS_STORE;
  return { columns: loader.length, groups: Object.keys(cards.groups).length, cards: cards.nodes.length };
}

/** Something was restored, and this tab has not said what to do with it. */
export function hasPreviousSession(): boolean {
  if (answered()) return false;
  const s = sessionSummary();
  return s.columns + s.groups + s.cards > 0;
}

export function recoverSession() {
  try { sessionStorage.setItem(GATE, "answered"); } catch { /* no storage: nothing to remember */ }
  setAnswered(true);
}

/**
 * Forget everything and start again through the one path the stores already have: empty
 * storage, then a reload. Not a store-by-store reset — that would be a second code path for the
 * same state, and the reload also drops every in-memory signal that was derived from it.
 */
export function resetSession(reload: () => void = () => location.reload()) {
  try {
    for (const key of Object.keys(sessionStorage)) {
      if (key.startsWith("dashi.")) sessionStorage.removeItem(key);
    }
  } catch { /* no storage: nothing to clear */ }
  reload();
}
```

- [ ] **Step 4: `App.tsx`**

Inside the `Router` render function, before the `<nav>`:

```tsx
          <Show when={hasPreviousSession()}>
            <div data-session-gate class="fixed inset-0 z-50 grid place-items-center bg-background/80">
              <div class="max-w-md rounded-sm border border-border bg-background p-4 shadow">
                <p class="mb-3 text-control-xs">
                  A previous session is here: {summaryText()}. Recover it, or start fresh?
                </p>
                <div class="flex gap-2">
                  <Button onClick={recoverSession}>Recover</Button>
                  <Button variant="danger" onClick={() => resetSession()}>Start fresh</Button>
                </div>
              </div>
            </div>
          </Show>
```

with `const summaryText = () => { const s = sessionSummary(); return [`${s.columns} column${s.columns === 1 ? "" : "s"} loaded`, `${s.groups} group${s.groups === 1 ? "" : "s"}`, `${s.cards} card${s.cards === 1 ? "" : "s"}`].join(" · "); };`. In the `<nav>`, next to `<ThemeToggle />`, wrap both in a `<span class="flex items-center gap-2">` and add:

```tsx
              <button
                type="button"
                onClick={() => { if (window.confirm("Discard the loaded table, filters and cards?")) resetSession(); }}
                class="inline-flex h-control-xs items-center rounded-sm px-2 text-control-xs text-primary-foreground/80 transition-colors hover:bg-primary-foreground/10 hover:text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
              >
                Start over
              </button>
```

(The class is `ThemeToggle`'s, so the two read as one control group.) Imports: `Show` from `solid-js`, `Button` from `./components/Button`, the four from `./session`.

- [ ] **Step 5: `TableView.tsx`**

In `gridOptions` add `overlayNoRowsTemplate: '<span class="p-2 text-control-xs">DashiBoard has no table loaded — load a file.</span>',` and in `getRows`'s `.then`, in the `!data` branch after `params.failCallback();`, add `gridApi?.showNoRowsOverlay();` with the comment: "A restored session shows a table the server may no longer hold (recovery restores the UI only, by decision 2026-09-16). The first page failing is how that surfaces; an empty grid would say nothing."

- [ ] **Step 6: Run the four UI checks** — all pass; 0 `STRICT_READ_UNTRACKED` (the gate's reads are in JSX).
- [ ] **Step 7: Mutation-test** — make `hasPreviousSession` return `false` always: the gate test fails. Restore. Make `resetSession` skip the key loop: the reset test fails. Restore.
- [ ] **Step 8: Commit** — `session: a gate for a restored document, and Start over`.

---

### Task 11: The card header folds instead of overflowing

**Files:**
- Modify: `dashiboard-ui/src/components/Disclosure.tsx:53` (summary classes)
- Modify: `dashiboard-ui/src/left-tabs/processing.tsx` (card header ~line 401–440: title unit, actions unit)
- Modify: `dashiboard-ui/src/components/GroupsEditor.tsx` (group header, same treatment)
- Test: `dashiboard-ui/src/left-tabs/processing.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
describe('the card header', () => {
  it('wraps its actions and truncates its title rather than overflowing', async () => {
    // Check 8 by hand: `dimensionality_reduction : dimensionality_reduction` pushed Remove past
    // the column's edge. jsdom has no layout, so this pins the classes and the full-text title.
    importCards({ nodes: [{ id: 'dimensionality_reduction', card: { type: 'dimensionality_reduction' } }], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    const summary = container.querySelector('[data-card-title]')!.closest('summary')!;
    expect(summary.className).toMatch(/flex-wrap/);
    const title = container.querySelector('[data-card-title]')!;
    expect(title.className).toMatch(/min-w-0/); expect(title.className).toMatch(/truncate/);
    expect(title.getAttribute('title')).toBe('dimensionality_reduction : dimensionality_reduction');
    expect(container.querySelector('[data-card-actions]')!.className).toMatch(/shrink-0/);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — no `[data-card-title]`.

- [ ] **Step 3: Implement**

`Disclosure.tsx` summary class: add `flex-wrap` (`"flex flex-wrap cursor-pointer …"`), with a comment: "Wraps: a long title (a card named after a long type) used to push the actions past the column's edge; folded to a second line, they stay in the pane."

`processing.tsx` card header: wrap the three title spans and the dot in

```tsx
                  <span
                    data-card-title
                    title={`${String(node.card.type)} : ${node.id || "unnamed"}`}
                    class="flex min-w-0 items-center gap-1.5 truncate"
                  >
                    …the existing type / ":" / id / dot spans…
                  </span>
```

and give the actions span `data-card-actions` and `class="ml-auto flex shrink-0 items-center gap-2"`. Same shape in `GroupsEditor.tsx` for `name : group ●` and its buttons (`data-group-title`, `data-group-actions`).

- [ ] **Step 4: Run the four UI checks** — all pass.
- [ ] **Step 5: Mutation-test** — remove `flex-wrap` from `Disclosure`: the test fails. Restore.
- [ ] **Step 6: Visual check (owner):** a `dimensionality_reduction` card in the left pane at the default window width — buttons on their own line, title intact; narrow the window until the title alone exceeds the row — it truncates with `…` and the full text is in the tooltip. Recorded in the report as "not verified in jsdom; owner's check".
- [ ] **Step 7: Commit** — `card header: actions fold to a new line, title truncates last`.

---

## Not a task

- The disappearance of `{cols: "TEMP"}` after a load (spec §3.4): not designed around. If Task 8's marker shows a value vanishing again, it becomes a task with a real-browser repro.
- `_id` in the results: kept, by decision.

## Self-review

- **Spec coverage.** §1.1 → T2 (`severity`), §1.2 → T2, §1.3 → T3, §1.4 → T1, §1.5 → T4 (both paths), §1.6 → T2 (the schema case already carried `issues`; the test pins it and the empty-group case joins it), §1.7 → the tests in T1–T4. §2.1 → T5, §2.2 → T6, §2.3 → T5, §2.4 → T5/T6 tests. §3.1 → T7, §3.2 → T8, §3.3 → T9, §3.5 → T7–T9 tests. §4 → T10 (all of 4.1–4.5, including the `TableView` overlay). §5 → T11. §7's rule → Global Constraints and every Julia step's comment/docstring.
- **Placeholders.** None: every step has its code or its exact command. Three spots tell the implementer to read the file for a helper name they must reuse (Task 9's `serveLoad`/`pick`, Task 10's `renderApp` mirrored from `renderHome`, Task 4's `Fun.case` rendering) and to report what they found.
- **Type consistency.** `ProbeIssue.severity?: "error" | "warning"` (T5) matches the server's `severity` (T2/T3); `askProbe(document: CardsStore)` (T5) is what T6 calls; `issuesForGroup(issues, name)` (T5) is what T6 uses; `reportRunIssues(issues: ProbeIssue[])` (T5) is what `results.tsx` calls; `resetSession(reload?)` (T10) is called with no argument from `App.tsx`; `Selector` must admit `through?: string[]` for T7's helpers — T7 says to widen it if it does not.
