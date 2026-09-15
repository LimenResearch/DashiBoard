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

---

## To try

Ordered so the good path is established before anything is broken.

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
