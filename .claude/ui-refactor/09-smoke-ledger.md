# 09 — Smoke ledger

A running record of what has been tried against a live server and what it did. Kept because the
interesting cases are the ones nothing catches, and those are easy to lose track of.

**Setup.** Server on `127.0.0.1:8090`, `julia --project=DashiBoard bin/launch.jl --port 8090
~/Documents/Limen/agentgraph/.dashi > /tmp/dashi.log 2>&1`. Log redirected so failures are readable
from outside the process; DashiBoard writes no request log, so everything else is inferred from the
DuckDB write-ahead log and the process's CPU time.

**Dataset.** `stress.csv`, 200 rows, built for this. Columns chosen so each one breaks a different
layer:

| column | as loaded | there to stress |
|---|---|---|
| `id` | int | a plain key |
| `TEMP`, `PRES` | float | the ordinary cases |
| `TEMP_rescaled` | float | collides with what `rescale TEMP suffix="rescaled"` emits (A13) |
| `cbwd` | string | a numeric method on text |
| `constant` | int, every row `42` | zero variance — `zscore` yields NaN (A12) |
| `mostly_null` | float, ~98% null | null propagation |
| `text_num` | int | *intended* as text holding numbers; DuckDB inferred int, so it is a spare numeric |
| `with space` | float | a name needing quoting |
| `single_group` | string, one value | `group_by` with a single bucket |

---

## Done

### 1. Load the table — ✅ 2026-09-14 12:02

Loaded `stress.csv` through the UI. Confirmed three ways: the monitor saw the write
(`wal 1958 -> 16979`) and the source vocabulary change; `probe-pipeline` reports all ten columns;
`fetch-data` reports **200 rows** and a first row that matches the file. Server log **0 bytes** —
nothing raised.

One thing the load itself decided, worth knowing before reading any later case: **`text_num` came
in as `int`.** It was written as quoted digits to be a string column, and DuckDB's CSV inference
took it as numeric anyway. So the "numeric method on a text column" case has to use `cbwd`.

### 13. The table at scale — ✅ 2026-09-16 (on `sdd/ui-fragility` @ 2a961bd, PR #169)

**Dataset.** `stress.parquet`, 1,000,000 rows, 7.8 MB, same ten columns and stress roles as
`stress.csv`, generated with DuckDB (seeded, single-threaded, so reproducible). Two differences:
`text_num` is genuinely text (`"1"`–`"9"`) because parquet carries types; `mostly_null` is non-null
on every `id % 50 == 0` (20,000 rows, the CSV's 2%). Recipe kept in the session transcript; it is
one `COPY (SELECT … FROM range(1, 1000001)) TO … (FORMAT PARQUET, COMPRESSION ZSTD)`.

**Getting it to show.** Written into the served directory while the server was up, it did not
appear in the Load tab. Not the server — `acceptable_paths()` walks `DATA_DIR` on every request —
but `FilePicker`, which fetches the list once at mount (A10, parked). A page reload showed it, and
in doing so exercised the `sessionStorage` persistence end to end: document, confirmations and tab
all came back.

**What the access log showed** (`JULIA_DEBUG=DashiBoard`, read in the terminal):

| moment | `fetch-data` | reading |
|---|---|---|
| table opened (load, and again after a run) | **1**, offset 0 | was 2 with both at offset 0 — ag-grid's deferred start called `setDatasource` a second time once the columns arrived; fixed in `0124bc0` by handing the grid its columns before its datasource, pinned by `TableView.test.tsx` |
| scrolling down | 1 per 100-row block | `cacheBlockSize: 100` |
| scrolling back to the top after more than 10 blocks | block 0 fetched again | `maxBlocksInCache: 10` evicted it — memory is bounded at ~1,000 rows whatever the table size |
| scrolling back within 10 blocks | none | served from the block cache |

This is the browser measurement the fragility plan's Task 8 Step 3 asked for and jsdom could not
give (no layout, so the grid never pages). A7 is closed on evidence, not inference.

### 14. The queue, run at scale — ✅ 2026-09-16 (ds-DashiUI @ 2806a54, `stress.parquet`, 1M rows)

Driven over HTTP against the live server (port 3000) rather than through the UI, so that each case
is one request with a measured time. Case 4 (a card with no name) is a client-only check
(`checkNode`, no request) and stays a UI/unit-test matter. Full table:
`scratchpad/stress-parquet-smoke.md` of this session.

| # | case | time | what came back |
|---|---|---|---|
| 1 | `load-files stress.parquet` | 2.1 s | 10 summaries; `text_num` is `categorical` — the parquet's text intent survives, unlike the CSV |
| 2 | `rescale zscore` on a group `inputs = [TEMP, PRES]`, suffix `z` | probe 5.4 s, run 9.4 s **first time**; 0.4 s after | valid; `TEMP_z`, `PRES_z` |
| 3 | `validate-card` on an empty `cluster` card | 0.45 s | one `required` issue, `missing = [method, inputs]`, one pointer per field |
| 5 | an empty group referenced by a card | probe 0.0 s, run 1.4 s | probe accepts; run fails `kind: execution`, **`UndefKeywordError: keyword argument args not assigned`** — an internal message where "group `empty` has no columns" belongs. The UI's `checkGroup` warns before this is reachable. |
| 6 | `zscore` on `cbwd` | 0.5 s | `execution`, `mean(VARCHAR)` — as expected |
| 7 | `zscore` on `constant` | 0.8 s | `execution`, `NaN not allowed to be written in JSON` — **A12 still open** |
| 8 | `pca`, 3 components from `TEMP` alone | 3.0 s | `execution`, `Binder Error: … add_result_column(… Type{Union{}})` — a different Binder error from the 200-row one, same class |
| 8b | `pca`, 2 components from `TEMP`, `PRES` | 1.3 s | valid; `component_1`, `component_2` |
| 9 | `rescale TEMP suffix = "rescaled"` | 0.6 s | accepted; `TEMP_rescaled` silently replaced — source range ±1.2 → output ±1.78. **A13 still open** |
| 10 | interval filter on `cbwd` | 0.2 s | `pipeline`, SQL error on `CREATE OR REPLACE TABLE selection` |
| 11 | list filter on a column that does not exist | 0.6 s | `pipeline`, `FunSQL.ReferenceError: cannot find nope` |
| 11b | **a filter that works, with no cards** (`cbwd in [NW, SE]`) | 0.3 s | **fails**: `pipeline`, `ArgumentError: reducing over an empty collection` — see A14 |
| 12 | two broken cards | probe 0.2 s | `2 schema validation errors` — both reported (A11 holds) |
| 13 | `fetch-data` at offset 999,900 | 0.01 s | 100 rows — paging cost is flat across the table |

**Timing, read as a whole.** The slow numbers are Julia compiling on first use (5.4 s probe,
9.4 s run), not the data: every later run on 1M rows is 0.2–1.4 s, and a page fetch at the far end
of the table is 10 ms. Responsiveness complaints on first use are a warm-up cost; anything slow
*after* that would be new.

**A14 (new).** A document with no cards cannot be run or probed: `Pipelines/src/group_api/dag.jl:23`
does `reduce(vcat, view(c.outputs, 1:n_nodes))` with no `init`, so `n_nodes == 0` throws. Reached
by: a filter-only run (a legitimate use of the Filter tab — filter, run, look), and the probe of an
empty document (the UI skips that probe when `nodes.length === 0`, which is why the Run button is
the first place it shows). Cases b/c/d in the scratch run: filter-only, nothing at all, and the
probe of filter-only all answer `kind: pipeline` with the internal message. Fix is
`init = String[]` (or whatever `c.outputs` holds) plus a test for a card-less document; the
"nothing at all" case may deserve its own plain message.

**Observation.** `_id` — the row-number column DashiBoard defines on `selection` for joining card
outputs (`ID_VAR`, `DashiBoard.jl:47`; `handlers.jl:262`) — comes back in every run's summaries,
so the results table shows an `_id` column the user never asked for. Pre-existing; exclude it from
what `summarize` reports, or from what the table shows.

### 15. The queue, by hand in the UI — ✅ 2026-09-16 (ds-DashiUI @ 2806a54, `stress.parquet`)

Same cases as entry 14, driven through the UI by the owner with the access log in view; each was
confirmed against entry 14's expectation. What the UI added on top of the HTTP run:

| # | by hand | found on the way |
|---|---|---|
| 2 | ✅ one `validate-card`, one `evaluate-pipeline` (~9 s first run), one `fetch-data` | — |
| 3 | ✅ two findings, on `method` and `inputs`; no probe call | — |
| 4 | ✅ one finding on the name, no request; the edit itself was one debounced probe | — |
| 5 | ✅ warning on the group; run fails with the internal `UndefKeywordError` | message → todo `empty-group-message` |
| 6 | ✅ `mean(VARCHAR)` | deleting the group `empty` left `groups:empty` on the card with no way to remove it → todo `dangling-references` |
| 7 | ✅ A12 | — |
| 8 | ✅ Binder Error; then 2 components from `TEMP`,`PRES` works | `dimensionality_reduction : dimensionality_reduction` pushes Remove out of the column → todo `card-header-overflow` |
| 9 | ✅ A13, silent | — |
| 10 | ✅ **by construction** — the Filter tab types its widgets from the summaries (checkboxes for a categorical column), so an interval on `cbwd` cannot be authored; HTTP-only | — |
| 11 | ✅ via persistence: list filter on `cbwd`, then load `pollution_test.parquet` → `cannot find cbwd` | the stale filter survived the load with no way to clear it; the card's `{cols: "TEMP"}` was **dropped** from the document (not reproduced in jsdom by the load alone) → both in todo `dangling-references` |
| 12 | ✅ `2 schema validation errors`, both cards | the run's failure pane shows the raw JSONSchema.jl text (`path: top-level instance: JSON.Object{String, Any}(…) schema key: required …`), where Confirm shows the same fault as two field pointers → todo below |

**New todo from 12.** A schema failure from **Run** should land where Confirm's does. The server
already has the structured form (`SchemaValidationErrors` → `issue_report`, per card, with
pointers); `evaluate-pipeline`'s failure carries it as prose in `errors`. Return `issues` alongside
(the field exists on the response) and have the results pane hand them to the cards, so the
pane says "2 cards are incomplete — see the marks" and the cards show `method`, `inputs`.

### 16. The queue, re-run against `sdd/post-smoke` — ✅ 2026-09-16 (PR #170 @ d0fa658, `stress.parquet`)

The branch's server launched from its worktree on port 3100 with its own cache
(`DASHIBOARD_CACHE=/tmp/dashi-cache-post-smoke`), the same HTTP-driven cases as entry 14. Full
table in the session scratchpad (`smoke-branch.md`). Everything unchanged by the branch answers as
in entry 14; what the branch set out to change now does:

| # | case | before (entry 14) | now |
|---|---|---|---|
| 5 | empty group referenced by a card | `execution`, `UndefKeywordError: keyword argument args not assigned` | **probe and run**: `valid=false`, `kind: pipeline`, one issue `error @ /groups/empty` reason `empty`, message "group `empty` has no columns" |
| 7 | `zscore` on `constant` (A12) | `execution`, `NaN not allowed to be written in JSON` | **valid**; `constant_z` in the summaries; `fetch-data` rows carry `null`, no `NaN`/`Infinity` token in any body |
| 9 | `rescale TEMP suffix = "rescaled"` (A13) | accepted silently | probe answers `valid=true` with `warning @ /nodes/0/card` reason `overwrites`; the run is allowed |
| 11b | a filter that works, no cards (A14) | `pipeline`, "reducing over an empty collection" | **valid**, 11 summaries (the filtered source) |
| 11c | nothing at all | same failure | **valid**, the source unchanged |
| 11d | probe of a groups-only document | (not tried) | **valid** — the continuous probe now runs for it, so an empty group is reported live before any card exists |
| 12 | two broken cards | both reported | both reported, each `severity: error`, on the probe and on the run |

Timings on 1M rows: load 0.5 s (cache warm), rescale runs 0.6–0.8 s, pca 3.1 s, filter-only run
0.7 s, page at offset 999,900 instant. First-use compilation is gone from these numbers because the
server had already answered once.

**Still open, by decision:** `_id` in the summaries (kept). **UI-side checks for the owner in a
browser against this branch's UI** (`DASHI_API=http://127.0.0.1:3100 pnpm run dev` from the
worktree's `dashiboard-ui/`): run failures landing on the cards; the empty-group finding on the group
(and its duplicate sentence in the top banner — parked); deleting a group clearing the cards that
used it; a missing chip's ×; filters clearing on a different table; the session gate flow; the header
fold/truncate.

---

## To try

Ordered so the good path is established before anything is broken. **Cases 2–12 were run at scale on
2026-09-16 (entry 14); 4 remains a UI-only check.** Open findings from that run: A12, A13, A14, the
empty-group message, `_id` in the summaries.

| # | case | what it should exercise | expected |
|---|---|---|---|
| 2 | a run that works: `rescale zscore` on `TEMP`, `PRES` | the whole good path — Confirm, run, the four result panes | accepted; `TEMP_rescaled`… wait, see note | 
| 3 | Confirm on an empty `cluster` card | the consolidated check: `validate-card`, two findings placed on `method` and `inputs` | two findings, no probe call |
| 4 | Confirm on a card with no name | `checkNode` — ours alone, no server counterpart | one finding, no request at all |
| 5 | an empty group, referenced by a card | `checkGroup` — ours alone; the server accepts it | warning in the UI; `execution` failure if run anyway |
| 6 | `zscore` on `cbwd` | a numeric method on text | `kind: execution`, `mean(VARCHAR)` |
| 7 | `zscore` on `constant` | **A12** — the run succeeds, the response cannot be encoded | `kind: execution`, `NaN not allowed…` |
| 8 | `pca`, `n_components = 3`, inputs `TEMP` only | the original failing run's shape | `kind: execution`, `Binder Error` |
| 9 | `rescale TEMP suffix = "rescaled"` | **A13** — output collides with an existing column | accepted everywhere, silently overwrites |
| 10 | interval filter on `cbwd` | the filter half `initialize_filters` never validates | `kind: pipeline`, SQL error |
| 11 | filter on a column that does not exist | same | `kind: pipeline`, `cannot find` |
| 12 | two broken cards at once | **A11** — both reported, not just the first | two issues |

**Note on case 2.** `rescale` on `TEMP` with the default suffix emits `TEMP_rescaled`, which
already exists — so the obvious "good run" is case 9 in disguise. Use a different suffix (`z`, say)
for the clean baseline, and keep `rescaled` for case 9 deliberately.
