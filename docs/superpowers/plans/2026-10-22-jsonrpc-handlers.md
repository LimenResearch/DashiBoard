# JSON-RPC Handlers: Finishing the Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make DashiBoard's server a JSON-RPC 2.0 server whose replies say success only by `result` vs `error`, move the frontend and ExperimentTracking onto it, and cut the test suite to substantive checks.

**Architecture:** Handlers validate params and return a thunk; `DashiBase.apply_handlers` runs it and wraps the outcome. Fixes land in that one layer (`DashiBase/src/json_rpc.jl`), DashiBoard's HTTP adapters (`middleware.jl`, `launch.jl`) gain batch replies, per-code status on the stream and one GET download, and handlers lose the `valid` success flag. The frontend keeps `postRequest`'s signature and maps route names to method + endpoint.

**Tech Stack:** Julia 1.11 (HTTP.jl, StructUtils, JSON), SolidJS + Vitest, DuckDB.

**Spec:** `docs/superpowers/specs/2026-10-20-jsonrpc-handlers-design.html` — read it first; section numbers below refer to it.

## Global Constraints

- **No commits.** Leave every change in the working tree; each task ends with a checkpoint (diff stat), not a commit. ExperimentTracking is a separate repo at `../ExperimentTracking.jl` — same rule.
- Minimal source changes: `DashiBase/src` and `DashiBoard/src` change only where a task requires it.
- Every Julia change outside `dashiboard-ui` carries its functional reason in a docstring or comment; comments state purpose, never history (no dates, measurements, "used to").
- DashiBase stays at version `2.0.0`; ExperimentTracking's compat is unchanged.
- Wire format: `"jsonrpc": "2.0"` on every reply; error object fields `code`, `message`, `data`.
- `id` is an integer or absent. Nothing else.
- `/rpc` and `/rpc-probe` always answer 200 (204 for no reply). `/rpc-stream` failure statuses: `-32700`→400, `-32600`→400, `-32602`→400, `-32601`→404, `-32603`→500.
- `valid` survives only as the document verdict in `validate-card` and the probe results.
- No author-visible UI change except: a data-less error now shows `error.message`.

## Review Focus

1. **A batch whose elements are all notifications** → no body, HTTP 204, not `[]` or a crash. Test in Task 1 (`apply_handlers` returns `nothing`) and Task 2 (`JSONHandler` answers 204).
2. **A JSON value of a non-integer number id (`1.5`) or a boolean id** → `-32600`, `id: null`, never a 500. Test in Task 1.
3. **A stream request whose thunk fails** (`fetch-data` on a missing table) → status 500 with the error envelope as `application/json`, and the frontend's table calls `failCallback` rather than rendering the envelope as rows. Test in Task 3 (status) and Task 4 (`TableView` with an `{error}` reply).
4. **The probe answering an `error`** (empty group) → the UI marks the group as it does today. Test in Task 4 (`probe.test.ts`: an `{error: {data: {issues: [...]}}}` reply yields `valid: false` and those issues).

(The CSV download before a run is not reachable: the link renders only inside `<Show when={result()}>` in `results.tsx`, and a failed run clears `result`.)

---

### Task 1: JSON-RPC 2.0 compliance in DashiBase

**Files:**
- Modify: `DashiBase/src/json_rpc.jl`
- Test: `DashiBase/test/runtests.jl` (new `@testset "json-rpc"` at the end)

**Interfaces:**
- Produces:
  - `JSONRequest`, `JSONSuccess`, `JSONFailure` each have field `jsonrpc::String = "2.0"` in place of `version::VersionNumber`; serialised key `"jsonrpc"`.
  - `JSONError(code::Int, message::String, data::Maybe{StringDict} = nothing)`; `StructuredException(data::StringDict)`.
  - `apply_handlers(handlers, s::AbstractString)` → `JSONSuccess | JSONFailure | Vector{Union{JSONSuccess,JSONFailure}} | Nothing`.
  - `apply_handlers(handlers, s::AbstractString, path::AbstractString)` → `(JSONSuccess, writer) | JSONFailure | Nothing`; a batch is a `JSONFailure` with code `-32600`.
  - `apply_handlers(::AbstractDict, f::JSONFailure) = f`.

- [ ] **Step 1: Write the failing test** — append to `DashiBase/test/runtests.jl`:

```julia
@testset "json-rpc" begin
    handlers = Dict{String, Any}("echo" => p -> (() -> p))
    rpc(s) = JSON.parse(JSON.json(DashiBase.apply_handlers(handlers, s)))

    ok = rpc("""{"jsonrpc":"2.0","id":1,"method":"echo","params":{"a":1}}""")
    @test ok == Dict("jsonrpc" => "2.0", "id" => 1, "result" => Dict("a" => 1))

    for bad in ("""{"id":1,"method":"echo","params":1}""", """{"jsonrpc":"1.0","id":1,"method":"echo","params":1}""")
        @test rpc(bad)["error"]["code"] == -32600
    end
    for id in ("\"abc\"", "1.5", "true")
        r = rpc("""{"jsonrpc":"2.0","id":$(id),"method":"echo","params":1}""")
        @test r["error"]["code"] == -32600 && r["id"] === nothing
    end
    @test rpc("""{"jsonrpc":"2.0","id":2,"method":"nope","params":1}""")["error"]["code"] == -32601
    @test rpc("{bad")["error"]["code"] == -32700

    batch = rpc("""[
        {"jsonrpc":"2.0","id":1,"method":"echo","params":1},
        {"jsonrpc":"2.0","method":"echo","params":2},
        {"jsonrpc":"2.0","id":3,"method":"nope","params":3},
        {"jsonrpc":"2.0","id":4}
    ]""")
    @test [r["id"] for r in batch] == [1, 3, 4]
    @test batch[1]["result"] == 1 && batch[2]["error"]["code"] == -32601 && batch[3]["error"]["code"] == -32600
    @test DashiBase.apply_handlers(handlers, """[{"jsonrpc":"2.0","method":"echo","params":1}]""") === nothing

    streamed = DashiBase.apply_handlers(handlers, """[{"jsonrpc":"2.0","id":1,"method":"echo","params":1}]""", tempname())
    @test streamed isa DashiBase.JSONFailure && streamed.error.code == -32600

    failure = DashiBase.json_error(DashiBase.internal_error, DashiBase.StructuredException(Dict{String, Any}("k" => 1)))
    @test JSON.parse(JSON.json(failure))["data"] == Dict("k" => 1)
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `julia --project=DashiBase -e 'using Pkg; Pkg.test()'`
Expected: FAIL in `json-rpc` (first assertion: `UndefVarError: make not defined` inside the error message).

- [ ] **Step 3: Implement in `DashiBase/src/json_rpc.jl`**
  - `make` → `StructUtils.make` (line 91).
  - Rename `version` → `jsonrpc::String = "2.0"` in the three structs; `metadata` → `data` in `JSONError`, `StructuredException`, and `json_error(::JSONErrorCode, ::StructuredException)`.
  - In `_get_request`, before `make`: if `id` is neither `Int` nor `nothing`, return `JSONFailure(; error)` with `id = nothing` and message "`id` must be an integer"; if `get(d, "jsonrpc", nothing) != "2.0"`, return an `invalid_request` failure carrying the (integer) id. Note `true isa Int` is false in Julia, as wanted.
  - Add `apply_handlers(::AbstractDict, failure::JSONFailure) = failure` (one comment: an invalid element of a batch is answered in place).
  - In the 3-arg string method, a vector request with a `path` returns an `invalid_request` failure "a streamed request cannot be a batch".

- [ ] **Step 4: Run tests to verify they pass**

Run: `julia --project=DashiBase -e 'using Pkg; Pkg.test()'`
Expected: all testsets pass.

- [ ] **Step 5: Checkpoint** — `git diff --stat DashiBase`; leave uncommitted.

---

### Task 2: DashiBoard server — `valid`, batches, stream statuses, GET download

**Files:**
- Modify: `DashiBoard/src/handlers.jl` (lines ~222–376 docstrings + returns, 642 kept, 762, 860, `get_processed_data`)
- Modify: `DashiBoard/src/middleware.jl` (`failure_report`, `JSONHandler`, `JSONStreamHandler`, `LoggingMiddleware` docstring's `valid` sentence)
- Modify: `DashiBoard/src/launch.jl` (register the GET route)
- Test: `DashiBoard/test/dashiboard.jl` (only the assertions this task breaks: `["valid"]` on success/failure replies and `["error"]["metadata"]` → `["error"]["data"]`, including the `only_error` helper)

**Interfaces:**
- Consumes: Task 1's `apply_handlers` return types and `JSONFailure.error.code`.
- Produces:
  - `stream_status(failure::JSONFailure)::Int` in `middleware.jl`, per the Global Constraints table.
  - `stream_response(h::JSONStreamHandler, stream::HTTP.Stream, s::AbstractString)`; `(h::JSONStreamHandler)(stream) = stream_response(h, stream, read(String, stream))`.
  - `const PROCESSED_DATA_REQUEST = """{"jsonrpc":"2.0","id":0,"method":"get-processed-data","params":{}}"""`.
  - Route `GET /get-processed-data` → `stream -> stream_response(stream_handler, stream, PROCESSED_DATA_REQUEST)`.
  - `CorsMiddleware` sets `CORS_RES_HEADERS` on every non-`OPTIONS` reply (`HTTP.setheader(stream, h)` before calling `handler(stream)`; headers are sent at `startwrite`). On `main` each handler added them (`main:DashiBoard/src/middleware.jl:128,141`); this branch dropped them, so a UI on another origin is refused by the browser. `cors404`/`cors405` drop their own copy so the header is not sent twice.
  - `get_processed_data` headers add `"Content-Disposition" => "attachment; filename=\"processed-data.csv\""`.
  - Reply shapes (spec 4.2): `read-*` → `{document}` / `{text, parsed}`; `write-*` → `{path}`; run → `{summaries, visualization, graph, report}`; error `data` → `{kind, errors, issues, …}` without `valid`. `validate-card` → `{valid, issues}` and probe → `{valid, kind, cols, nodes, …}` unchanged.

- [ ] **Step 1: Update the in-process assertions first** — in `dashiboard.jl`, replace every `["error"]["metadata"]` with `["error"]["data"]`; delete assertions of `valid` on read/write/run replies and on error `data` (they become absences: add one `@test !haskey(res["result"], "valid")` in `document and configurations` and one `@test !haskey(res["error"]["data"], "valid")` in `runtime-error`). Keep `valid` assertions on `validate-card` and probe results.

- [ ] **Step 2: Run to verify they fail**

Run: `cd DashiBoard && julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL on the two new `!haskey` assertions (and the broken tail, fixed in Task 3 — ignore errors after line ~1153 for now).

- [ ] **Step 3: Implement**
  - Remove `valid` per the Produces shapes; update the docstrings that describe `{valid: true, …}` (the `read_document` docstring's "tells a reply from a failure by `valid` alone" becomes "by `result` vs `error`").
  - `JSONHandler`: annotation widens to include `AbstractVector`; a vector serialises as an array, `nothing` stays 204.
  - `stream_response`: on `JSONFailure`, `setstatus(stream, stream_status(res))` with `JSON_HEADERS`; success and 204 paths unchanged. Docstring of `stream_status` says why: a stream may itself be JSON, so the status is what tells a file from an error.
  - CORS in `CorsMiddleware` as above; its docstring says it is the one place reply headers for cross-origin use are set (Task 3's live test asserts the exact header list on a reply and on a 404).
  - Register the GET route in `launch.jl` beside `/rpc-stream`, with a comment: a link cannot carry a JSON-RPC body, and only a download the browser makes itself streams to disk.

- [ ] **Step 4: Run tests** — same command. Expected: all in-process testsets before line ~1153 pass.

- [ ] **Step 5: Checkpoint** — `git diff --stat DashiBoard/src`.

---

### Task 3: Cut the DashiBoard test suite; rewrite the live and tail tests

**Files:**
- Modify: `DashiBoard/test/dashiboard.jl`
- Modify: `DashiBoard/test/workspace.jl` (lines ~232, ~259 only)

**Interfaces:**
- Consumes: Task 2's routes, `stream_status`, `PROCESSED_DATA_REQUEST`; existing `post`, `post_probe` helpers (lines ~249–271).
- Produces: a `first_free_port(range)` helper at file top level (moved out of the `request` testset), used by the live testset and `workspace.jl`'s launcher test if it needs one.

- [ ] **Step 1: Apply the spec 5.3 table verbatim** — CUT `LoggingMiddleware` (with `FakeStream` and its `Logging` imports), `cards`, `probe-clean` (move its one assertion into `pipeline-groups and data download`), `skip-probe` (merge into `probe-noid` as `for call in (post_probe, post)`); TRIM `pointers` to the unset default + `@test_throws ArgumentError pointer(:nowhere)`, `card-ir` shape checks, the five `write-configuration` refusals into one loop over `(path, text, overwrite)` tuples, `empty-group`'s repeated checks, `root_causes`' wrapper-text lines; KEEP the rest, dropping repeated `kind`/`severity` lines.

- [ ] **Step 2: Rewrite lines ~1153–1334 inside the `mktempdir() do data_dir` block** (so `data_dir`, `model_dir`, `training_dir`, `cards_doc` are in scope):
  - `@testset "a missing data directory"`, `"configurations in a flat workspace"`, `"files by folder"`: build `get_handlers(dir; …)` and call `apply_handlers` via a local `post`-like closure over those handlers. Keep the substantive cases listed in spec 5.3.
  - One `@testset "server"`: `launch(data_dir; port, async = true, model_dir, training_dir)`, then:

```julia
rpc(endpoint, method, params) = HTTP.post(url * endpoint; status_exception = false,
    body = JSON.json((; jsonrpc = "2.0", id = 1, method, params)))
resp = rpc("rpc", "list-files", Dict())
@test resp.status == 200 && haskey(JSON.parse(String(copy(resp.body))), "result")
@test resp.headers == [DashiBoard.CORS_RES_HEADERS..., "Content-Type" => "application/json", "Content-Length" => string(length(resp.body))]
@test haskey(JSON.parse(String(rpc("rpc-probe", "evaluate-pipeline", pipeline_doc).body))["result"], "nodes")
resp = rpc("rpc-stream", "fetch-data", Dict("processed" => false, "limit" => 2, "offset" => 0))
@test resp.status == 200 && length(JSON.parse(String(resp.body))["values"]) == 2
@test rpc("rpc-stream", "nope", Dict()).status == 404
resp = HTTP.get(url * "get-processed-data"; status_exception = false)
@test resp.status == 200 && HTTP.header(resp, "Content-Type") == "text/csv"
@test HTTP.header(resp, "Content-Disposition") == "attachment; filename=\"processed-data.csv\""
@test ("Access-Control-Allow-Origin" => "*") in HTTP.post(url * "nowhere"; status_exception = false).headers
@test HTTP.options(url * "rpc").headers == [DashiBoard.CORS_OPTIONS_HEADERS..., "Content-Length" => "0"]
close(server)
```

  `pipeline_doc` is any probe document already used above (e.g. the one in `pipeline-groups`).

- [ ] **Step 3: `workspace.jl`** — lines ~232 and ~259 post `{"jsonrpc":"2.0","id":1,"method":"get-card-ir","params":{}}` / `"list-files"` to `/rpc`; the stop check must observe a connection failure, not any exception (catch only `HTTP.Exceptions.ConnectError`/`IOError`).

- [ ] **Step 4: Run** — `cd DashiBoard && julia --project=. -e 'using Pkg; Pkg.test()'`. Expected: all pass. Then `wc -l DashiBoard/test/dashiboard.jl` — expected roughly 900 (spec 5.3).

- [ ] **Step 5: Checkpoint** — `git diff --stat DashiBoard/test`; the test diff should be net negative by several hundred lines.

---

### Task 4: Frontend onto JSON-RPC

**Files:**
- Modify: `dashiboard-ui/src/requests.ts`, `apiRoutes.ts`, `probe.ts`, `components/Documents.tsx`, `left-tabs/results.tsx`, `components/TableView.tsx`, `left-tabs/processing.tsx` (only where a failure is read), `stores.ts` only if types demand it
- Test: `requests.test.ts`, `probe.test.ts`, `components/Documents.test.tsx`, `left-tabs/results.test.tsx`, `components/TableView.test.tsx`, `apiRoutes.test.ts`; other test files only where a failure mock or a success-flag `valid` appears

**Interfaces:**
- Produces in `requests.ts`:
  - `type RpcError = { error: { code: number; message: string; data?: Record<string, unknown> | null } }`
  - `isRpcError(x: unknown): x is RpcError` — a non-array object with own key `error`.
  - `failureOf(e: RpcError): { errors: string[]; issues?: unknown[]; kind?: string; [k: string]: unknown }` — `e.error.data ?? { errors: [e.error.message] }`.
  - `postRequest(page, body, def)` — unchanged signature; resolves to the unwrapped `result`, an `RpcError`, or `def` when unreachable or non-JSON.
  - `postBlob(page, body)` — returns `{blob, filename} | RpcError | null`.
  - Endpoint map: `"probe-pipeline"` → method `"evaluate-pipeline"` on `rpc-probe`; `"bundle-pipeline" | "fetch-data" | "get-processed-data"` → `rpc-stream`; else `rpc`. Stream: `response.ok` → body is the result (`fetch-data` JSON) or the blob; otherwise parse the JSON error envelope.
  - `API_ROUTES = ["/rpc", "/rpc-probe", "/rpc-stream", "/get-processed-data"]`.

- [ ] **Step 1: Write failing tests** — in `requests.test.ts`:
  - `postRequest('list-files', {}, null)` posts to `/rpc` a body equal to `{jsonrpc: '2.0', id: expect.any(Number), method: 'list-files', params: {}}` and resolves to the `result` of the mocked reply.
  - `postRequest('probe-pipeline', doc, null)` posts to `/rpc-probe` with `method: 'evaluate-pipeline'`.
  - A mocked `{jsonrpc, id, error: {code: -32602, message: 'm', data: null}}` resolves to that `{error}`; `failureOf` of it is `{errors: ['m']}`.
  - `postRequest('fetch-data', …)` with a 200 raw `{values, length}` resolves to it; with status 500 and an error envelope resolves to `{error}`.
  - `postBlob('bundle-pipeline', …)`: 400 + envelope → `{error}`; 200 zip → `{blob, filename}` (replace the existing `{ json: { valid: false … } }` case).
  - `probe.test.ts`: an `{error: {code: -32602, message: 'x', data: {issues: [I], errors: ['e']}}}` reply yields a probe store with `valid: false`, `issues: [I]` (Review Focus 5).
  - `TableView.test.tsx`: an `{error}` reply for `fetch-data` calls `failCallback` (Review Focus 4).
  - `results.test.tsx`: after a successful run the CSV link points at `/get-processed-data` (existing gating by `result()` is unchanged).

- [ ] **Step 2: Run** — `cd dashiboard-ui && npx vitest run`. Expected: the new cases FAIL.

- [ ] **Step 3: Implement** — `requests.ts` per Interfaces; callers: `Documents.tsx` 87/106/123 test `isRpcError(reply)` and `say(failureOf(reply).errors)`; `Reply` loses `valid`; `results.tsx` 125 replaces `answer.valid === false` with `isRpcError(answer)` reading `failureOf(answer)`; `probe.ts` maps an `RpcError` to `usableProbe({ ...failureOf(reply), valid: false })`; `TableView.tsx` treats `isRpcError(data)` like `null`; `processing.tsx` callers that read a failure use `failureOf`. Update failure mocks in the other test files to `{ error: { code, message, data } }` and drop success-flag `valid` from success mocks.

- [ ] **Step 4: Run** — `npx vitest run && npm run lint && npm run build`. Expected: all green.

- [ ] **Step 5: Checkpoint** — `git diff --stat dashiboard-ui`.

---

### Task 5: ExperimentTracking onto DashiBase's layer

**Files (repo `../ExperimentTracking.jl`):**
- Delete: `src/api/json_rpc.jl`
- Modify: `src/ExperimentTracking.jl` (drop the include; `using DashiBase: apply_handlers, apply_middleware, probe_middleware, JSONSuccess, JSONFailure`), `src/api/router.jl` (`JSONHandler` accepts a vector reply), `src/api/handlers.jl:66` (`probe_result` drops `valid`)
- Test: `test/rpc.jl`, `test/api.jl`

**Interfaces:**
- Consumes: Task 1's DashiBase API (local checkout: `Pkg.develop(path = "../DashiBoard/DashiBase")` in ET's test env for the duration; revert before handing back, since ET pins `rev = "main"`).

- [ ] **Step 1: Update tests** — every request body gains `"jsonrpc":"2.0"` (`test/api.jl:24`, the named tuples in `test/rpc.jl`); `dict["result"]["valid"] === true` becomes `@test !haskey(dict["result"], "valid")`; `metadata` → `data`; keep `rpc.jl`'s batch testset as ET's batch coverage.
- [ ] **Step 2: Run** — `cd ../ExperimentTracking.jl && julia --project=. -e 'using Pkg; Pkg.develop(path="../DashiBoard/DashiBase"); Pkg.test()'`. Expected: FAIL (ET still uses its own layer and sends `valid`).
- [ ] **Step 3: Implement** the file changes above; any ET symbol the deleted file defined that DashiBase lacks is a sign of drift — stop and report it rather than re-adding it.
- [ ] **Step 4: Run** — same command. Expected: pass. Then revert the `develop` (`git checkout Manifest.toml Project.toml` in ET if they changed).
- [ ] **Step 5: Checkpoint** — `git -C ../ExperimentTracking.jl diff --stat`.

---

### Task 6: Whole-branch verification

- [ ] **Step 1:** `cd DashiBoard && julia --project=. -e 'using Pkg; Pkg.test()'` — full suite (includes DashiBase, DataIngestion, Pipelines, StreamlinerCore). Save output to a file and read it whole on failure.
- [ ] **Step 2:** `cd dashiboard-ui && npx vitest run && npm run lint && npm run build`.
- [ ] **Step 3: Smoke run in the browser** — launch on a workspace with `pollution.csv`, then: load the table, edit a card (probe fires), validate a card with a missing field, run, page the results table, Download CSV (saved as `processed-data.csv`), Download the pipeline bundle, and trigger a bundle failure (missing model configuration) to see its message.
- [ ] **Step 4:** Report `git diff --stat main...` plus working tree for both repos — expected: tests net negative by several hundred lines; source changes small.
