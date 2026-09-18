# Documents in the data directory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cards and filters documents are listed, read and written by the server inside its data directory, through the same picker tables use, filtered by kind; the browser's whole-disk file dialog goes.

**Architecture:** Three new routes in `DashiBoard/src/handlers.jl` — `list-files` (every file under the data directory, classified `table | cards | filters`, a JSON told apart by content), `read-document` and `write-document` — all resolving paths through one `resolve_in_data_dir`, which `load-files` adopts too. In the UI, `FilePicker` gains a `kind`, and one new `Documents` component (picker + Load, name + Save, Download, one error block) is mounted in the Process tab and the Filter tab; it knows neither store and takes `document()` and `onLoad(document)`.

**Tech Stack:** Julia 1.12 (HTTP.jl, JSON.jl 1.8, TOML stdlib) in `DashiBoard/`; SolidJS 2 (rc.6) + TypeScript, vitest + `@solidjs/testing-library` in `dashiboard-ui/`; pnpm.

**Spec:** `docs/superpowers/specs/2026-09-18-documents-in-the-data-directory-design.md`

## Global Constraints

- Only `DashiBoard/` and `dashiboard-ui/` change. `Pipelines/` and `DataIngestion/` are not touched: the team leader is working in Pipelines.
- Work in a worktree on a side branch `sdd/documents-in-data-dir` from `ds-DashiUI`, at the commit that holds the picker's refresh button (`FilePicker.tsx` with `ask()` and `Button`'s `label` prop — uncommitted in the main checkout when this plan was written; it must be committed first, because a worktree starts from a commit and Task 3 edits that version of the file). One commit per task on the side branch; nothing lands on `ds-DashiUI` — the owner reviews and merges.
- Every Julia change carries its functional reason in a docstring or a comment (owner's rule, 2026-09-16).
- TDD both sides: every test is written first and watched failing; a test that passes before its production change is mutation-checked (break the production line, watch it fail, restore).
- UI verification before every UI commit, from `dashiboard-ui/`: `npx vitest run` (all green, `0` lines containing `STRICT_READ_UNTRACKED`), `npx tsc --noEmit`, `pnpm run lint` (no *new* warnings — 20 at baseline), `pnpm run build`.
- Julia verification before every Julia commit, from the repository root: `DASHIBOARD_CACHE=$(mktemp -d) julia --project=DashiBoard/test DashiBoard/test/runtests.jl > /tmp/dashi-julia.log 2>&1; echo "exit $?"` — the suite downloads `pollution.csv` (network) and includes the other packages' tests, so allow 20 minutes; exit 0 is the bar. If `--project=DashiBoard/test` complains about a dependency, run `julia --project=DashiBoard/test -e 'using Pkg; Pkg.resolve()'` once.
- Redirect every run to a file and read the whole file; never grep-filter a run you are diagnosing. The suite logs three `@error` blocks from deliberate-failure tests; they are not failures.
- A Solid 2 signal must not be written during a component's own setup (`REACTIVE_WRITE_IN_OWNED_SCOPE`); a store setter takes a function (`setState(reconcile(x))`, never `setState(x)`).
- Copy, verbatim: buttons `Load cards`, `Load filters`, `Save cards`, `Save filters`, `Download cards`, `Download filters`; checkbox `replace an existing file`; default names `cards.json`, `filters.json`; the picker's refresh stays `aria-label="refresh the file list"`.

---

## File structure

| file | responsibility after this plan |
|---|---|
| `DashiBoard/Project.toml` | gains the `TOML` stdlib |
| `DashiBoard/src/DashiBoard.jl` | `using TOML: TOML`; drops the `acceptable_paths` import (Task 3) |
| `DashiBoard/src/handlers.jl` | `data_directory`, `resolve_in_data_dir`, `document_kind`, `parse_document`, `file_kind`; handlers `list_files`, `read_document`, `write_document`; `load_files` checks its paths |
| `DashiBoard/src/launch.jl` | registers `/list-files`, `/read-document`, `/write-document`; drops `/get-acceptable-paths` (Task 3) |
| `DashiBoard/test/dashiboard.jl` | fixtures in the test's `data_dir`; request tests for the three routes, the path check, a missing directory |
| `dashiboard-ui/vite.config.ts` | the dev proxy names the three routes; drops `/get-acceptable-paths` |
| `dashiboard-ui/src/components/FilePicker.tsx` | `kind` prop; asks `list-files`; `refresh` exposed to a parent |
| `dashiboard-ui/src/components/Documents.tsx` | **new** — the document row for one kind |
| `dashiboard-ui/src/left-tabs/processing.tsx` | `loadCards(document): Promise<string[]>`; mounts `<Documents kind="cards">`; its own upload block and signal go |
| `dashiboard-ui/src/left-tabs/filtering.tsx` | mounts `<Documents kind="filters">`; loads through `filtersCodec.decode`; saves and downloads `filtersCodec.encode` |
| `dashiboard-ui/src/components/JSON.tsx`, `src/requests.ts` | `UploadJSONButton` and `loadJSON` deleted |

Task order: 1 → 2 (server) → 3 → 4 → 5 → 6 (UI). Tasks 3–6 need 1–2 only at run time in a browser; their tests mock the server.

---

### Task 1: One path function, the listing, and `load-files` checking its paths

**Files:**
- Modify: `DashiBoard/Project.toml` (`[deps]`), `DashiBoard/src/DashiBoard.jl:15` (after `using JSON: JSON`)
- Modify: `DashiBoard/src/handlers.jl:1-12` (add the helpers and `list_files` after `get_acceptable_paths`; change `load_files`)
- Modify: `DashiBoard/src/launch.jl:16` (register the route)
- Test: `DashiBoard/test/dashiboard.jl` (fixtures right after the download at `:166-169`; a new `@testset "files"` inside `@testset "request"`; a missing-directory server after `close(server)` at `:565`)

**Interfaces:**
- Consumes: `DataIngestion.DATA_DIR`, `DataIngestion.is_supported`, `json_read`, `json_response`, `failure_report(kind, exception)`.
- Produces (Julia, module `DashiBoard`):
  - `data_directory()::String` — the absolute, normalised data directory (`pwd()` when `DATA_DIR[]` is empty, as `DataIngestion.acceptable_paths` has it).
  - `resolve_in_data_dir(path::AbstractString)::String` — the absolute path, or `ArgumentError("`<path>` is outside the data directory")`.
  - `document_kind(parsed)::Union{String, Nothing}` — `"cards"`, `"filters"` or `nothing`.
  - `parse_document(full::AbstractString)` — JSON or TOML by extension, else `ArgumentError`.
  - `file_kind(full::AbstractString)::Union{String, Nothing}` — `"table"`, `"cards"`, `"filters"` or `nothing`.
  - Route `POST /list-files` → `[{"path": "sub/x.parquet", "kind": "table"}, …]`, sorted by path.

- [ ] **Step 1: Add the fixtures and the failing tests**

In `DashiBoard/test/dashiboard.jl`, right after the `Downloads.download(...)` call (`:166-169`), build the fixtures in the same `data_dir`:

```julia
    # Fixtures for the file routes: one of each kind, a JSON that is a real table, a JSON that
    # does not parse, and hidden entries — all in the directory the server is launched on.
    cards_doc = Dict("nodes" => [Dict("id" => "r", "card" => Dict("type" => "rescale"))], "groups" => Dict{String, Any}())
    write(joinpath(data_dir, "cards.json"), JSON.json(cards_doc))
    write(joinpath(data_dir, "cards.toml"), "groups = {}\n[[nodes]]\nid = \"r\"\n[nodes.card]\ntype = \"rescale\"\n")
    write(joinpath(data_dir, "filters.json"), JSON.json(Dict("numerical" => Dict("TEMP" => Dict("min" => 0, "max" => 1)), "categorical" => Dict{String, Any}())))
    mkdir(joinpath(data_dir, "sub"))
    write(joinpath(data_dir, "sub", "table.json"), JSON.json([Dict("a" => 1), Dict("a" => 2)]))
    write(joinpath(data_dir, "broken.json"), "{ not json")
    write(joinpath(data_dir, ".hidden.json"), JSON.json(cards_doc))
    mkdir(joinpath(data_dir, ".cache"))
    write(joinpath(data_dir, ".cache", "cards.json"), JSON.json(cards_doc))
    write(joinpath(data_dir, "notes.md"), "not a table, not a document")
```

Inside `@testset "request" begin`, right after `url = …` (`:222`), add:

```julia
        @testset "files" begin
            post(route, body) = JSON.parse(HTTP.post(url * route, body = JSON.json(body), status_exception = false).body)

            # The listing names every file the UI may pick, with what it is. A JSON is told from
            # a table by content, so the kind survives a rename; what does not parse, what is
            # hidden and what is neither table nor document are not listed.
            listed = post("list-files", Dict())
            @test [(f["path"], f["kind"]) for f in listed] == [
                ("cards.json", "cards"),
                ("cards.toml", "cards"),
                ("filters.json", "filters"),
                ("pollution.csv", "table"),
                (joinpath("sub", "table.json"), "table"),
            ]

            # `load-files` joined `..` without looking; a path outside the data directory is now
            # a failure envelope, not a read.
            escaped = post("load-files", Dict("files" => ["../pollution.csv"]))
            @test escaped["valid"] == false
            @test occursin("outside the data directory", only(escaped["errors"]))
        end
```

After `close(server)` (`:565`), still inside the `mktempdir` block:

```julia
    # A data directory that does not exist used to make every listing throw: a 500 with an
    # empty body, logged as 200 (see `LoggingMiddleware`), and an empty picker with no reason.
    @testset "a missing data directory" begin
        nowhere_port = first_free_port(8281:8380)
        nowhere = DashiBoard.launch(
            joinpath(data_dir, "does-not-exist");
            port = nowhere_port, async = true, model_directory, training_directory
        )
        resp = HTTP.post("http://127.0.0.1:$(nowhere_port)/list-files", body = "{}", status_exception = false)
        @test resp.status == 200
        @test JSON.parse(resp.body) == []
        close(nowhere)
    end
```

- [ ] **Step 2: Run the suite, watch the new tests fail**

```bash
DASHIBOARD_CACHE=$(mktemp -d) julia --project=DashiBoard/test DashiBoard/test/runtests.jl > /tmp/dashi-julia-t1-red.log 2>&1; echo "exit $?"
```
Read the whole log. Expected: `list-files` answers the router's 404 so `JSON.parse` of its body throws or the comparison fails; the `load-files` assertion fails because the reply is a 500, not an envelope; the missing-directory test fails on the 404. Every other testset passes.

- [ ] **Step 3: Add the TOML dependency**

In `DashiBoard/Project.toml`, add to `[deps]`, keeping the list alphabetical:

```toml
TOML = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
```

Then `julia --project=DashiBoard -e 'using Pkg; Pkg.resolve()'` and `julia --project=DashiBoard/test -e 'using Pkg; Pkg.resolve()'`. `TOML` is a standard library: no `[compat]` entry. In `DashiBoard/src/DashiBoard.jl`, after `using JSON: JSON`:

```julia
# TOML is Pipelines' native configuration format, so a cards document written by hand is as
# likely to be TOML as JSON; the file routes read both (handlers.jl, `parse_document`).
using TOML: TOML
```

- [ ] **Step 4: The helpers and the handler**

In `DashiBoard/src/handlers.jl`, after `get_acceptable_paths` (`:1-5`), add:

```julia
"""
    data_directory() -> String

The directory every file route is confined to, absolute and normalised. `pwd()` when the server
was launched without one, which is `DataIngestion.acceptable_paths`'s own rule — so the listing
here and the loader there agree on where "here" is.
"""
function data_directory()
    dir = DataIngestion.DATA_DIR[]
    return normpath(abspath(isempty(dir) ? pwd() : dir))
end

"""
    resolve_in_data_dir(path) -> String

`path`, read relative to the data directory, as an absolute path — or an `ArgumentError` if it
leaves that directory.

The one path function of the file routes. A client names files by the relative paths
`list-files` gave it, but nothing stops a request from saying `../../etc/passwd`, and
`load-files` used to join such a path without looking. Compared through `relpath` rather than
`startswith`, which would let `/data-evil` pass for `/data`.
"""
function resolve_in_data_dir(path::AbstractString)
    outside() = throw(ArgumentError("`$(path)` is outside the data directory"))
    isabspath(path) && outside()
    base = data_directory()
    full = normpath(joinpath(base, path))
    rel = relpath(full, base)
    (rel == ".." || startswith(rel, ".." * Base.Filesystem.path_separator)) && outside()
    return full
end

# What makes a parsed file a document of the UI rather than a table: the keys `Download cards`
# and `Download filters` write. Told by content, not by name, so the kind survives a rename and
# a `.json` that is a real table (DataIngestion's `json_reader`) stays a table.
const DOCUMENT_SHAPES = (
    "cards" => ("nodes", "groups"),
    "filters" => ("numerical", "categorical"),
)

"""
    document_kind(parsed) -> Union{String, Nothing}

`"cards"`, `"filters"`, or `nothing` when `parsed` is neither.
"""
function document_kind(parsed)
    parsed isa AbstractDict || return nothing
    for (kind, required) in DOCUMENT_SHAPES
        all(key -> haskey(parsed, key), required) && return kind
    end
    return nothing
end

"""
    parse_document(full) -> parsed

Read a JSON or a TOML file, by extension. TOML because it is Pipelines' configuration format
and a cards document written by hand is as likely to be one; JSON because it is what the UI
writes.
"""
function parse_document(full::AbstractString)
    ext = lowercase(last(splitext(full)))
    ext == ".json" && return JSON.parsefile(full)
    ext == ".toml" && return TOML.parsefile(full)
    throw(ArgumentError("`$(basename(full))` is neither JSON nor TOML"))
end

"""
    file_kind(full) -> Union{String, Nothing}

`"table"`, `"cards"`, `"filters"`, or `nothing` for a file the UI has no use for.

A JSON or TOML file is parsed to find out: a document is small, a JSON table is rare, and a peek
at the whole file is what lets a renamed document keep its kind. One that does not parse is
`nothing` — a half-written file must not break the listing, and the listing is not where a parse
error is reported (`read_document` is).
"""
function file_kind(full::AbstractString)
    ext = lowercase(last(splitext(full)))
    if ext in (".json", ".toml")
        parsed = try
            parse_document(full)
        catch
            return nothing
        end
        kind = document_kind(parsed)
        isnothing(kind) || return kind
        return ext == ".json" ? "table" : nothing
    end
    return DataIngestion.is_supported(full) ? "table" : nothing
end

"""
    list_files(req)

Every file under the data directory the UI may pick, as `[{path, kind}]` — relative paths,
subfolders included, sorted. Replaces `get-acceptable-paths`, which listed tables only: cards and
filters documents used to come in through the browser's own file dialog, which shows the whole
disk, while tables were confined to this directory. One listing, one visibility.

Hidden files and folders are skipped. A data directory that does not exist answers `[]` and
warns: `walkdir` throws on it, which reached the client as a 500 with an empty body and the log
as a 200 (`LoggingMiddleware` records the status set *before* a throw).
"""
function list_files(req::HTTP.Request)
    _ = json_read(req)
    base = data_directory()
    if !isdir(base)
        @warn "the data directory does not exist" base
        return json_response([])
    end
    files = @NamedTuple{path::String, kind::String}[]
    for (root, dirs, names) in walkdir(base)
        # `walkdir` is top-down, so pruning `dirs` in place keeps it out of hidden folders.
        filter!(dir -> !startswith(dir, "."), dirs)
        for name in names
            startswith(name, ".") && continue
            kind = file_kind(joinpath(root, name))
            isnothing(kind) && continue
            push!(files, (; path = normpath(relpath(root, base), name), kind))
        end
    end
    sort!(files, by = file -> file.path)
    return json_response(files)
end
```

Change `load_files` (`:7-12`) to:

```julia
function load_files(req::HTTP.Request)
    spec = json_read(req)
    # Checked here, not in `DataIngestion.parse_paths`, which joins `..` without looking and is
    # not ours to change: a client names files by the relative paths `list-files` gave it, and a
    # path that leaves the data directory is refused before anything is read.
    try
        foreach(resolve_in_data_dir, spec["files"])
    catch exception
        return json_response(failure_report("load", exception))
    end
    DataIngestion.load_files(REPOSITORY[], spec)
    summaries = DataIngestion.summarize(REPOSITORY[], "source")
    return json_response(summaries)
end
```

In `DashiBoard/src/launch.jl`, after the `/get-acceptable-paths` registration (`:16`):

```julia
    HTTP.register!(router, "POST", "/list-files", HTTP.streamhandler(list_files))
```

- [ ] **Step 5: Run the suite, watch it pass**

```bash
DASHIBOARD_CACHE=$(mktemp -d) julia --project=DashiBoard/test DashiBoard/test/runtests.jl > /tmp/dashi-julia-t1-green.log 2>&1; echo "exit $?"
```
Expected: exit 0. If the listing order differs from the test's, the fixture names sort as written (`cards.json`, `cards.toml`, `filters.json`, `pollution.csv`, `sub/table.json`); a mismatch is a bug in the walk, not in the test.

- [ ] **Step 6: Mutation-check the hidden-folder pruning**

Delete the `filter!(dir -> …, dirs)` line, re-run: the listing test must FAIL (`.cache/cards.json` appears). Restore, re-run: exit 0.

- [ ] **Step 7: Commit**

```bash
git add DashiBoard/Project.toml DashiBoard/src/DashiBoard.jl DashiBoard/src/handlers.jl DashiBoard/src/launch.jl DashiBoard/test/dashiboard.jl
git commit -m "files: one listing with kinds, one path function; load-files checks its paths"
```

---

### Task 2: `read-document` and `write-document`

**Files:**
- Modify: `DashiBoard/src/handlers.jl` (after `list_files`), `DashiBoard/src/launch.jl` (two registrations)
- Test: `DashiBoard/test/dashiboard.jl` (extend `@testset "files"`)

**Interfaces:**
- Consumes: `resolve_in_data_dir`, `parse_document`, `document_kind`, `failure_report` (Task 1).
- Produces:
  - `POST /read-document {"path", "kind"}` → `{"valid": true, "document": {…}}`, or `failure_report("document", e)` = `{"valid": false, "kind": "document", "errors": [...], "issues": []}`.
  - `POST /write-document {"path", "kind", "document", "overwrite"}` → `{"valid": true, "path": "<path>"}`, or the same failure envelope.

- [ ] **Step 1: Write the failing tests**

Append inside `@testset "files"`, after the `load-files` assertions:

```julia
            # Reading: JSON and TOML spell the same document; the kind asked for must be the kind
            # found; nothing outside the directory, nothing that is not there.
            from_json = post("read-document", Dict("path" => "cards.json", "kind" => "cards"))
            from_toml = post("read-document", Dict("path" => "cards.toml", "kind" => "cards"))
            @test from_json["valid"] == true
            @test from_json["document"]["nodes"][1]["id"] == "r"
            @test from_toml["document"]["nodes"][1]["card"]["type"] == "rescale"
            @test from_toml["document"]["groups"] == Dict()

            wrong_kind = post("read-document", Dict("path" => "filters.json", "kind" => "cards"))
            @test wrong_kind["valid"] == false
            @test wrong_kind["kind"] == "document"
            @test occursin("not a cards document", only(wrong_kind["errors"]))

            for path in ("../cards.json", joinpath(data_dir, "cards.json"))
                outside = post("read-document", Dict("path" => path, "kind" => "cards"))
                @test outside["valid"] == false
                @test occursin("outside the data directory", only(outside["errors"]))
            end
            missing_file = post("read-document", Dict("path" => "nope.json", "kind" => "cards"))
            @test occursin("does not exist", only(missing_file["errors"]))
            unparsable = post("read-document", Dict("path" => "broken.json", "kind" => "cards"))
            @test unparsable["valid"] == false

            # Writing: a document round-trips inside the directory; an existing file is kept
            # unless the author says replace; the shape must match the kind; JSON only.
            doc = from_json["document"]
            saved = post("write-document", Dict("path" => "sub/mine.json", "kind" => "cards", "document" => doc, "overwrite" => false))
            @test saved == Dict("valid" => true, "path" => "sub/mine.json")
            @test ("sub/mine.json", "cards") in [(f["path"], f["kind"]) for f in post("list-files", Dict())]
            @test post("read-document", Dict("path" => "sub/mine.json", "kind" => "cards"))["document"] == doc

            again = post("write-document", Dict("path" => "sub/mine.json", "kind" => "cards", "document" => doc, "overwrite" => false))
            @test occursin("already exists", only(again["errors"]))
            replaced = post("write-document", Dict("path" => "sub/mine.json", "kind" => "cards", "document" => doc, "overwrite" => true))
            @test replaced["valid"] == true

            @test occursin("not a filters document", only(post("write-document", Dict("path" => "f.json", "kind" => "filters", "document" => doc, "overwrite" => false))["errors"]))
            @test occursin("outside the data directory", only(post("write-document", Dict("path" => "../x.json", "kind" => "cards", "document" => doc, "overwrite" => false))["errors"]))
            @test occursin(".json", only(post("write-document", Dict("path" => "x.toml", "kind" => "cards", "document" => doc, "overwrite" => false))["errors"]))
            @test occursin("folder", only(post("write-document", Dict("path" => "nowhere/x.json", "kind" => "cards", "document" => doc, "overwrite" => false))["errors"]))
            @test !isfile(joinpath(data_dir, "f.json"))
```

On Linux `joinpath("sub", "mine.json")` is `"sub/mine.json"`; the literal is used because it is what a client sends.

- [ ] **Step 2: Run, watch them fail** — the command of Task 1 Step 2 with `-t2-red.log`. Expected: the new assertions fail on the 404s.

- [ ] **Step 3: The two handlers**

In `handlers.jl`, after `list_files`:

```julia
"""
    read_document(req)

A cards or filters document from the data directory: `{valid: true, document}`, or the failure
envelope every other route uses, with the server's sentence. Wrapped rather than returned bare,
so a client tells a reply from a failure by `valid` alone, never by guessing at a document's keys.

The counterpart of the browser's file dialog, which read a local file the server never saw and
showed the whole disk. `kind` is what the client expects: a filters file picked where cards
were asked for is refused here, with a sentence, rather than loaded into the wrong store.
"""
function read_document(req::HTTP.Request)
    spec = json_read(req)
    answer = try
        path, kind = spec["path"], spec["kind"]
        full = resolve_in_data_dir(path)
        isfile(full) || throw(ArgumentError("`$(path)` does not exist"))
        document = parse_document(full)
        document_kind(document) == kind || throw(ArgumentError("`$(path)` is not a $(kind) document"))
        (; valid = true, document)
    catch exception
        failure_report("document", exception)
    end
    return json_response(answer)
end

"""
    write_document(req)

Save a cards or filters document into the data directory, as indented JSON: `{valid: true, path}`
or the failure envelope. What makes a document round-trip where it can be loaded again — the
browser's Download puts the file in a folder `list-files` never sees.

Refuses: a path outside the directory; a name that does not end in `.json` (TOML is read, not
written); a document whose shape is not `kind`'s; a folder that does not exist (no folders are
created on a client's word); an existing file, unless `overwrite` is `true`.
"""
function write_document(req::HTTP.Request)
    spec = json_read(req)
    answer = try
        path, kind, document = spec["path"], spec["kind"], spec["document"]
        full = resolve_in_data_dir(path)
        lowercase(last(splitext(full))) == ".json" ||
            throw(ArgumentError("documents are saved as JSON: `$(path)` does not end in .json"))
        document_kind(document) == kind || throw(ArgumentError("this is not a $(kind) document"))
        isdir(dirname(full)) || throw(ArgumentError("the folder of `$(path)` does not exist"))
        (isfile(full) && get(spec, "overwrite", false) !== true) &&
            throw(ArgumentError("`$(path)` already exists"))
        write(full, JSON.json(document; pretty = true))
        (; valid = true, path)
    catch exception
        failure_report("document", exception)
    end
    return json_response(answer)
end
```

In `launch.jl`, after the `/list-files` registration:

```julia
    HTTP.register!(router, "POST", "/read-document", HTTP.streamhandler(read_document))
    HTTP.register!(router, "POST", "/write-document", HTTP.streamhandler(write_document))
```

- [ ] **Step 4: Run, watch it pass** — `-t2-green.log`, exit 0.

- [ ] **Step 5: Mutation-check the overwrite guard** — replace `get(spec, "overwrite", false) !== true` with `false`: the "already exists" assertion must FAIL. Restore; exit 0.

- [ ] **Step 6: Commit**

```bash
git add DashiBoard/src/handlers.jl DashiBoard/src/launch.jl DashiBoard/test/dashiboard.jl
git commit -m "documents: read and write inside the data directory, JSON and TOML in, JSON out"
```

---

### Task 3: The picker asks `list-files` and filters by kind; `get-acceptable-paths` retires

**Files:**
- Modify: `dashiboard-ui/src/components/FilePicker.tsx`, `dashiboard-ui/src/left-tabs/loading.tsx:53` (`kind="table"`)
- Modify: `dashiboard-ui/vite.config.ts:35` (proxy list)
- Modify: `DashiBoard/src/handlers.jl:1-5` (delete `get_acceptable_paths`), `DashiBoard/src/launch.jl:16` (its registration), `DashiBoard/src/DashiBoard.jl:45` (`acceptable_paths` leaves the import)
- Test: `dashiboard-ui/src/components/FilePicker.test.tsx`

**Interfaces:**
- Consumes: `POST /list-files` → `[{path, kind}]`.
- Produces:
  - `export type FileKind = "table" | "cards" | "filters"`
  - `FilePicker` props: `{ kind: FileKind; required?: boolean; multiple?: boolean; onChange?: (value: string | string[]) => void; label?: string; refreshRef?: (refresh: () => void) => void }`. `label` replaces the hard-coded "Choose files"; `refreshRef` hands the parent the function the `↻` button calls, so a save can refresh the list.

- [ ] **Step 1: Rewrite the picker's tests**

In `FilePicker.test.tsx`, change the default mock and every render, and add the kind test. The `beforeEach` becomes:

```ts
const LISTING = [
  { path: 'a.parquet', kind: 'table' },
  { path: 'b.parquet', kind: 'table' },
  { path: 'cards.json', kind: 'cards' },
  { path: 'sub/filters.json', kind: 'filters' },
];
beforeEach(() => {
  postRequest.mockReset();
  postRequest.mockImplementation(() => Promise.resolve(LISTING));
});
```

Every `<FilePicker multiple />` becomes `<FilePicker kind="table" multiple />`. In the refresh test the second answer becomes `[...LISTING, { path: 'c.parquet', kind: 'table' }]`, the `null`-then-answer test's second answer `[{ path: 'a.parquet', kind: 'table' }]`, and both count calls with `c[0] === 'list-files'`. Add:

```ts
  it('offers only the files of its kind', async () => {
    // One listing serves three pickers: tables on the Load tab, cards and filters documents on
    // theirs. A cards file must not be offered as a table, nor a table as a document.
    const { container } = render(() => <FilePicker kind="cards" />);
    await waitFor(() => expect(container.textContent).toContain('cards.json'));
    expect(container.textContent).not.toContain('a.parquet');
    expect(container.textContent).not.toContain('sub/filters.json');
    expect(postRequest.mock.calls[0][0]).toBe('list-files');
  });

  it('hands its parent the refresh, so a save can re-list', async () => {
    let refresh!: () => void;
    const { container } = render(() => <FilePicker kind="cards" refreshRef={(f) => { refresh = f; }} />);
    await waitFor(() => expect(container.textContent).toContain('cards.json'));
    postRequest.mockImplementation(() => Promise.resolve([{ path: 'mine.json', kind: 'cards' }]));
    refresh();
    await waitFor(() => expect(container.textContent).toContain('mine.json'));
  });
```

- [ ] **Step 2: Run, watch them fail**

```bash
npx vitest run src/components/FilePicker.test.tsx > /tmp/t3-red.log 2>&1; cat /tmp/t3-red.log
```
Expected: every test fails — the picker posts `get-acceptable-paths` and maps strings, so `[object Object]` is listed and `kind` is ignored.

- [ ] **Step 3: The picker**

`FilePicker.tsx` becomes:

```tsx
import { Combobox } from "./Combobox";
import { Button } from "./Button";

import { createSignal } from "solid-js";
import { postRequest } from "../requests";
import * as _ from "lodash";

/** What `list-files` says a file is. A JSON is told from a table by content, server-side. */
export type FileKind = "table" | "cards" | "filters";
type Listed = { path: string; kind: FileKind };

type FilePickerProps = {
  /** Which files of the data directory this picker offers. */
  kind: FileKind;
  required?: boolean;
  onChange?: (value: string | string[]) => void;
  multiple?: boolean;
  /** Defaults to "Choose files", which is what the Load tab says. */
  label?: string;
  /** Receives the function the refresh button calls, for a parent that changes the directory
   *  itself — a save — and wants the new file listed without the author pressing `↻`. */
  refreshRef?: (refresh: () => void) => void;
};

export function FilePicker(props: FilePickerProps) {
  // Asked once at mount, and again on the button. A memo over the promise asked exactly once:
  // if the server was still starting, `postRequest` answered `null`, the list stayed empty and
  // nothing asked again — a reload during the same boot gave the same nothing (owner,
  // 2026-09-18). The server walks the directory on every request, so asking is all it takes.
  //
  // One listing for every picker: `list-files` names each file's kind, and tables, cards and
  // filters documents are confined to the same directory through the same control.
  const [files, setFiles] = createSignal<Listed[]>([]);
  // `true` from the start rather than set on the way in: Solid 2 refuses a signal write during a
  // component's own setup (`REACTIVE_WRITE_IN_OWNED_SCOPE`), and the first request goes out
  // from exactly there. The replies write from a microtask, which is fine.
  const [asking, setAsking] = createSignal(true);
  const request = () =>
    postRequest("list-files", {}, null)
      .then((answer: unknown) => setFiles(Array.isArray(answer) ? (answer as Listed[]) : []))
      .finally(() => setAsking(false));
  void request();
  function ask() {
    setAsking(true);
    void request();
  }
  props.refreshRef?.(ask);
  const options = () =>
    files()
      .filter((file) => file.kind === props.kind)
      .map((file) => ({ label: file.path, value: file.path }));
  const selectClass = "text-primary font-semibold py-2 w-full text-left";
  const id = _.uniqueId("load_");
  return (
    <>
      <label for={id} class={selectClass}>
        {props.label ?? "Choose files"}
      </label>
      <div class="flex items-start gap-2">
        <div class="min-w-0 grow">
          <Combobox
            id={id}
            required={props.required}
            onChange={props.onChange}
            multiple={props.multiple}
            options={options()}
          ></Combobox>
        </div>
        <Button
          disabled={asking()}
          title="ask the server for the files again"
          label="refresh the file list"
          onClick={ask}
        >
          ↻
        </Button>
      </div>
    </>
  );
}
```

In `loading.tsx:53`: `<FilePicker kind="table" required multiple onChange={setFiles}></FilePicker>`.

In `vite.config.ts`, replace `'/get-acceptable-paths',` with:

```ts
        '/list-files',
        '/read-document',
        '/write-document',
```

- [ ] **Step 4: Retire the old route**

`handlers.jl`: delete `get_acceptable_paths` (`:1-5`). `launch.jl`: delete its `HTTP.register!` line. `DashiBoard.jl:45`: `using DataIngestion: Filter, DataIngestion`. `git grep -n "acceptable" DashiBoard/ dashiboard-ui/src dashiboard-ui/vite.config.ts` must return nothing but comments that say what it replaced.

- [ ] **Step 5: Run both sides**

```bash
npx vitest run src/components/FilePicker.test.tsx > /tmp/t3-green.log 2>&1; cat /tmp/t3-green.log
```
then the full UI verification of the Global Constraints, then the Julia suite (exit 0 — nothing tested the old route).

- [ ] **Step 6: Commit**

```bash
git add dashiboard-ui/src/components/FilePicker.tsx dashiboard-ui/src/components/FilePicker.test.tsx dashiboard-ui/src/left-tabs/loading.tsx dashiboard-ui/vite.config.ts DashiBoard/src
git commit -m "picker: one listing, filtered by kind; get-acceptable-paths retires"
```

---

### Task 4: `Documents` — load, save, download, one error block

**Files:**
- Create: `dashiboard-ui/src/components/Documents.tsx`
- Test: `dashiboard-ui/src/components/Documents.test.tsx`

**Interfaces:**
- Consumes: `FilePicker` and `FileKind` (Task 3), `Button`, `Input`, `Checkbox`, `DownloadJSONButton`, `postRequest`.
- Produces:

```ts
type DocumentsProps = {
  kind: Exclude<FileKind, "table">;
  /** The document as it is saved and downloaded — already encoded, plain JSON. */
  document: () => unknown;
  /** Put a loaded document in place. Resolves to the sentences nobody could place on an item
   *  (a loop; an unreachable server); empty when there is nothing to say. */
  onLoad: (document: unknown) => Promise<string[]> | string[];
};
export function Documents(props: DocumentsProps): JSXElement
```

DOM hooks the tests and the later tasks rely on: `[data-documents="cards"|"filters"]` on the root; `[data-document-error]` on the error block; the three buttons by their text.

- [ ] **Step 1: Write the failing tests**

Create `Documents.test.tsx`:

```tsx
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';
import { createSignal, flush } from 'solid-js';

const postRequest = vi.fn();
const downloadJSON = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  downloadJSON: (...args: unknown[]) => downloadJSON(...args),
  getURL: (page: string) => `/${page}`,
  setApiBase: vi.fn(), apiBase: () => '',
}));
// The real picker is a Choices.js widget; what matters here is which path it hands back.
vi.mock('./FilePicker', () => ({
  FilePicker: (props: { kind: string; onChange?: (v: string) => void; refreshRef?: (f: () => void) => void }) => {
    props.refreshRef?.(() => refreshed());
    return <button data-pick onClick={() => props.onChange?.(`sub/${props.kind}.json`)}>pick</button>;
  },
}));
const refreshed = vi.fn();

import { Documents } from './Documents';

const CARDS = { nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} };
const serve = (replies: Record<string, unknown>) =>
  postRequest.mockImplementation((page: string) => Promise.resolve(replies[page] ?? null));

beforeEach(() => { postRequest.mockReset(); downloadJSON.mockReset(); refreshed.mockReset(); });
afterEach(cleanup);

describe('Documents', () => {
  it('loads the picked file through the server and hands the document to its owner', async () => {
    serve({ 'read-document': { valid: true, document: CARDS } });
    const onLoad = vi.fn(() => Promise.resolve([]));
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={onLoad} />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    fireEvent.click(getByText('Load cards'));
    await waitFor(() => expect(onLoad).toHaveBeenCalledWith(CARDS));
    expect(postRequest).toHaveBeenCalledWith('read-document', { path: 'sub/cards.json', kind: 'cards' }, null);
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it('cannot load before a file is picked', () => {
    const { getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={() => []} />);
    expect((getByText('Load cards') as HTMLButtonElement).disabled).toBe(true);
  });

  it('shows the server\'s sentence when a load fails, and loads nothing', async () => {
    serve({ 'read-document': { valid: false, kind: 'document', errors: ['`x.json` is not a cards document'], issues: [] } });
    const onLoad = vi.fn(() => []);
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={onLoad} />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    fireEvent.click(getByText('Load cards'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toContain('is not a cards document');
    expect(onLoad).not.toHaveBeenCalled();
  });

  it('says so when the server cannot be reached', async () => {
    serve({});
    const { container, getByText } = render(() => <Documents kind="filters" document={() => ({})} onLoad={() => []} />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    fireEvent.click(getByText('Load filters'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toMatch(/could not reach/i);
  });

  it('shows what the loader could not place, and clears it when the document is edited', async () => {
    serve({ 'read-document': { valid: true, document: CARDS } });
    const [doc, setDoc] = createSignal<unknown>(CARDS);
    const { container, getByText } = render(() => (
      <Documents kind="cards" document={doc} onLoad={() => Promise.resolve(['The input graph contains at least one loop.'])} />
    ));
    fireEvent.click(container.querySelector('[data-pick]')!);
    fireEvent.click(getByText('Load cards'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toContain('at least one loop');
    setDoc({ ...CARDS, nodes: [] });
    await flush();
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it('saves the document under the name given, and re-lists', async () => {
    serve({ 'write-document': { valid: true, path: 'mine.json' } });
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={() => []} />);
    const name = container.querySelector('input[aria-label="file name"]') as HTMLInputElement;
    expect(name.value).toBe('cards.json');
    name.value = 'mine.json';
    fireEvent.change(name);
    fireEvent.click(getByText('Save cards'));
    await waitFor(() => expect(refreshed).toHaveBeenCalled());
    expect(postRequest).toHaveBeenCalledWith(
      'write-document', { path: 'mine.json', kind: 'cards', document: CARDS, overwrite: false }, null,
    );
  });

  it('replaces an existing file only when the author says so', async () => {
    serve({ 'write-document': { valid: false, kind: 'document', errors: ['`cards.json` already exists'], issues: [] } });
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={() => []} />);
    fireEvent.click(getByText('Save cards'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toContain('already exists');
    expect(refreshed).not.toHaveBeenCalled();

    serve({ 'write-document': { valid: true, path: 'cards.json' } });
    fireEvent.click(container.querySelector('input[type="checkbox"]')!);
    fireEvent.click(getByText('Save cards'));
    await waitFor(() => expect(refreshed).toHaveBeenCalled());
    expect(postRequest.mock.calls.at(-1)![1]).toMatchObject({ overwrite: true });
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it('downloads exactly what it saves', () => {
    const { getByText } = render(() => <Documents kind="filters" document={() => ({ numerical: {}, categorical: { cbwd: ['NW'] } })} onLoad={() => []} />);
    fireEvent.click(getByText('Download filters'));
    expect(downloadJSON.mock.calls[0][0]).toEqual({ numerical: {}, categorical: { cbwd: ['NW'] } });
  });
});
```

- [ ] **Step 2: Run, watch them fail**

```bash
npx vitest run src/components/Documents.test.tsx > /tmp/t4-red.log 2>&1; cat /tmp/t4-red.log
```
Expected: the file fails to import `./Documents`.

- [ ] **Step 3: The component**

Create `Documents.tsx`:

```tsx
import { createEffect, createSignal, For, Show } from "solid-js";

import { Button } from "./Button";
import { Checkbox } from "./Checkbox";
import { DownloadJSONButton } from "./JSON";
import { FilePicker, type FileKind } from "./FilePicker";
import { Input } from "./Input";
import { postRequest } from "../requests";

// The document row of a tab: load one from the data directory, save this one into it, download
// it. One component for cards and for filters, because the three actions are the same and only
// the kind and the owner differ — it knows neither store.
//
// It replaces the browser's own file dialog. That dialog read a file on the author's machine,
// which the server never saw, and so showed the whole disk, while tables were confined to the
// server's data directory and picked from a list. One visibility now (owner, 2026-09-18): the
// server lists, reads and writes documents inside that directory, through the same picker.

type DocumentKind = Exclude<FileKind, "table">;

type DocumentsProps = {
  kind: DocumentKind;
  /** The document as it is saved and downloaded — already encoded, plain JSON. */
  document: () => unknown;
  /** Put a loaded document in place. Resolves to the sentences nobody could place on an item
   *  (a loop; an unreachable server); empty when there is nothing to say. */
  onLoad: (document: unknown) => Promise<string[]> | string[];
};

type Reply = { valid?: boolean; document?: unknown; errors?: string[] } | null;
const UNREACHABLE = "Could not reach DashiBoard — is the server running?";
const sentences = (reply: Reply) =>
  reply === null ? [UNREACHABLE] : reply.errors?.length ? reply.errors : ["The server refused, without saying why."];

export function Documents(props: DocumentsProps) {
  const [picked, setPicked] = createSignal<string | null>(null);
  const [name, setName] = createSignal(`${props.kind}.json`);
  const [overwrite, setOverwrite] = createSignal(false);
  const [busy, setBusy] = createSignal(false);
  let refresh: () => void = () => {};

  // What could not be said on an item — a load or save the server refused, or what the loader
  // could not place. It belongs to the document as it was when it was said, so an edit clears
  // it: the comparison is on the serialised document, the same string a save would write.
  const [report, setReport] = createSignal<string[] | null>(null);
  let reportedOn: string | null = null;
  const say = (lines: string[]) => {
    reportedOn = lines.length > 0 ? JSON.stringify(props.document()) : null;
    setReport(lines.length > 0 ? lines : null);
  };
  createEffect(
    () => JSON.stringify(props.document()),
    (json) => {
      if (reportedOn !== null && json !== reportedOn) {
        reportedOn = null;
        setReport(null);
      }
    },
  );

  async function load() {
    const path = picked();
    if (path === null) return;
    setBusy(true);
    try {
      const reply = (await postRequest("read-document", { path, kind: props.kind }, null)) as Reply;
      if (reply === null || reply.valid !== true) return say(sentences(reply));
      const loose = await props.onLoad(reply.document);
      // Said about the document as loaded, which is only in place once the owner's write has
      // settled — a tick later than `onLoad` returning.
      queueMicrotask(() => say(loose));
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    setBusy(true);
    try {
      const reply = (await postRequest(
        "write-document",
        { path: name(), kind: props.kind, document: props.document(), overwrite: overwrite() },
        null,
      )) as Reply;
      if (reply === null || reply.valid !== true) return say(sentences(reply));
      say([]);
      refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div data-documents={props.kind} class="flex flex-col gap-2 p-3">
      <FilePicker
        kind={props.kind}
        label={`A ${props.kind} file in the data directory`}
        onChange={(value) => setPicked(Array.isArray(value) ? (value[0] ?? null) : value || null)}
        refreshRef={(f) => { refresh = f; }}
      />
      <div class="flex flex-wrap items-center gap-2">
        <Button disabled={busy() || picked() === null} onClick={() => void load()}>
          Load {props.kind}
        </Button>
        <Input
          aria-label="file name"
          value={name()}
          onChange={(event) => setName(event.currentTarget.value.trim())}
        />
        <Checkbox label="replace an existing file" checked={overwrite()} onChange={setOverwrite} />
        <Button disabled={busy() || name() === ""} onClick={() => void save()}>
          Save {props.kind}
        </Button>
        <DownloadJSONButton data={props.document()} name={name() || `${props.kind}.json`}>
          Download {props.kind}
        </DownloadJSONButton>
      </div>
      {/* Same dress as a failed run's text under Run: the server's own sentence about the
          document. Gone on the next load or save, and on the next edit. */}
      <Show when={report()} keyed>
        {(lines: string[]) => (
          <div
            data-document-error
            class="rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-control-xs text-destructive"
          >
            <For each={lines}>
              {(line: string) => <p class="font-mono break-words whitespace-pre-wrap">{line}</p>}
            </For>
          </div>
        )}
      </Show>
    </div>
  );
}
```

`DownloadJSONButton` reads `props.data` when clicked (`JSON.tsx:40`), so it downloads the document as it is at the click.

- [ ] **Step 4: Run, watch them pass**

```bash
npx vitest run src/components/Documents.test.tsx > /tmp/t4-green.log 2>&1; cat /tmp/t4-green.log
```
If "clears it when the document is edited" fails because the report is cleared at once, the `queueMicrotask` ran before the owner's write: in this test `document` does not change on load, so that cannot be the cause — look instead for `reportedOn` being taken before `props.document()` reflects the load, and fix the order, not the test.

- [ ] **Step 5: Mutation-check** — make `save` send `overwrite: false` always: "replaces an existing file only when the author says so" must FAIL. Restore.

- [ ] **Step 6: Full UI verification, then commit**

```bash
git add dashiboard-ui/src/components/Documents.tsx dashiboard-ui/src/components/Documents.test.tsx
git commit -m "Documents: load, save and download one kind of document through the data directory"
```

---

### Task 5: The Process tab loads cards through `Documents`

**Files:**
- Modify: `dashiboard-ui/src/left-tabs/processing.tsx` — `uploadCards` → `loadCards`, returning its sentences; its `uploadReport` signal, the `CARDS_JSON` effect beside it and the `[data-upload-error]` block go; the Download/Upload pair (`:602-612`) becomes `<Documents kind="cards" …>`
- Test: `dashiboard-ui/src/left-tabs/processing.test.tsx` — the `describe('an upload asks')` block (added 2026-09-18) becomes `describe('loading a cards document asks')`

**Interfaces:**
- Consumes: `Documents` (Task 4), `checkNames`, `rejectFromIssues`, `documentFindings`, `askProbe`, `importCards`, `exportCards`.
- Produces: `loadCards(value: unknown): Promise<string[]>` (module-private) — imports, places what it can, resolves to what it cannot.

- [ ] **Step 1: Rewrite the four tests to enter through Load**

In `processing.test.tsx`, remove `import { loadJSON } from '../requests';`. In the block's helpers, the document now arrives from the server, so `withProbe` also serves `read-document` and `list-files`, and `upload` presses Load:

```ts
  const withProbe = (reply: unknown, doc: unknown) =>
    postRequest.mockImplementation((page: string, body: unknown) =>
      Promise.resolve(
        page === 'get-card-ir'
          ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                     const full = structuredClone(payload) as Record<string, unknown>;
                     return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
        : page === 'probe-pipeline' ? reply
        : page === 'validate-card' ? { valid: true, issues: [] }
        : page === 'read-document' ? { valid: true, document: doc }
        : [],
      ),
    );
  const load = async (container: HTMLElement) => {
    await waitFor(() => expect(container.querySelector('[data-documents="cards"] [data-pick]')).not.toBeNull());
    fireEvent.click(container.querySelector('[data-documents="cards"] [data-pick]')!);
    await flush();
    fireEvent.click([...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Load cards')!);
    await flush();
    await new Promise((r) => setTimeout(r, 0));
    await flush();
  };
```

At the top of the file, next to the `vi.mock('../requests', …)`, mock the picker — choosing in a Choices.js widget is the picker's own tests' business, and `loading.test.tsx` mocks it the same way; `Documents` itself stays real, because this block is its integration with `loadCards`:

```ts
vi.mock('../components/FilePicker', () => ({
  FilePicker: (props: { onChange?: (v: string) => void }) =>
    <button data-pick onClick={() => props.onChange?.('doc.json')}>pick</button>,
}));
```

Each test calls `withProbe(<its probe reply>, <its document>)`, renders, waits for `[data-documents="cards"]`, calls `await load(container)`, and keeps its assertions, with `[data-upload-error]` renamed `[data-document-error]` and "The uploaded document does not build:" dropped from the loop test (the block now holds the server's sentence alone — assert `'at least one loop'` only). Do not mock `Documents` here.

- [ ] **Step 2: Run, watch them fail**

```bash
npx vitest run src/left-tabs/processing.test.tsx -t "loading a cards document asks" > /tmp/t5-red.log 2>&1; cat /tmp/t5-red.log
```
Expected: all four fail — there is no `[data-documents="cards"]`.

- [ ] **Step 3: `loadCards`, and the mount**

In `processing.tsx`, replace the `uploadReport` signal, `uploadedJson`, its `createEffect(CARDS_JSON, …)` and `uploadCards` with:

```tsx
  /**
   * Loading a cards document is an act of asking.
   *
   * The document is put in place exactly as it came — a broken one included, because fixing it
   * here is what the form is for (owner, 2026-09-18) — and then asked about once, on the
   * author's behalf, from that same copy. What the server points at is rejected on its item,
   * the way a failed run's issues are; a taken name is ours to place (`checkNames`), since the
   * server reports it with no pointer; whatever is left has no item, and is handed back to
   * `Documents`, which says it under its buttons until the next edit. Nothing is confirmed: an
   * item the probe has nothing against stays amber, because nobody looked at it.
   *
   * Its own `askProbe`, not the continuous probe's reply: that one writes the store and nothing
   * else, and by the time it answers the document may already be a later one.
   */
  async function loadCards(value: unknown): Promise<string[]> {
    // One plain copy is what is stored, what is asked about and what the verdicts bind to —
    // not `exportCards()` read back right after `importCards`, which on Solid 2 may still be
    // the previous document in this tick.
    const document = structuredClone(value) as CardsStore;
    importCards(document);
    const taken = checkNames(document.nodes);
    for (const { index, finding } of taken) {
      recordVerdict(`node:${index}`, document.nodes[index], "rejected", [finding]);
    }
    const answer = await askProbe(document);
    if (answer === null) {
      return ["Could not reach DashiBoard to check this document — is the server running?"];
    }
    rejectFromIssues(answer.issues, document);
    // With a taken name placed above, the server's one build error for this document is that
    // same duplicate id (construction stops there — measured), already on the later card; what
    // else there is surfaces once the names are fixed.
    if (taken.length > 0) return [];
    return documentFindings(answer).map((finding) => finding.message);
  }
```

Replace the `<div class="flex gap-2">` holding `DownloadJSONButton`/`UploadJSONButton` **and** the `[data-upload-error]` `<Show>` after it with:

```tsx
      {/* `CARDS_JSON`, not `exportCards`: `Documents` clears what it said when the document
          changes, and it learns that by reading `document()` in an effect. `exportCards` reads a
          `snapshot`, which tracks nothing; `CARDS_JSON` is the memo persistence already builds
          over the whole store, so parsing it back is a tracked read of the same document. */}
      <Documents
        kind="cards"
        document={() => JSON.parse(CARDS_JSON()) as CardsStore}
        onLoad={loadCards}
      />
```

Imports: add `import { Documents } from "../components/Documents";`, remove `DownloadJSONButton, UploadJSONButton` and `emptyCards` if nothing else uses them (tsc will say). `CARDS_JSON` is already imported.

- [ ] **Step 4: Run, watch them pass; full UI verification**

```bash
npx vitest run src/left-tabs/processing.test.tsx > /tmp/t5-green.log 2>&1; cat /tmp/t5-green.log
```

- [ ] **Step 5: Commit**

```bash
git add dashiboard-ui/src/left-tabs/processing.tsx dashiboard-ui/src/left-tabs/processing.test.tsx
git commit -m "process: cards load through Documents; loading asks, and hands back what it cannot place"
```

---

### Task 6: The Filter tab loads, saves and downloads through the codec; the browser dialog is deleted

**Files:**
- Modify: `dashiboard-ui/src/left-tabs/filtering.tsx:6,82-96`
- Modify: `dashiboard-ui/src/components/JSON.tsx` (delete `UploadJSONButton`, `UploadProps`), `dashiboard-ui/src/requests.ts:49-58` (delete `loadJSON`)
- Modify: every test whose `vi.mock('../requests', …)` lists `loadJSON` — remove the key (`git grep -ln loadJSON dashiboard-ui/src`)
- Test: `dashiboard-ui/src/left-tabs/filtering.test.tsx`

**Interfaces:**
- Consumes: `Documents` (Task 4), `filtersCodec.encode` / `.decode` (`stores.ts:66-79`), `FILTERS_STORE`.
- Produces: no exports.

- [ ] **Step 1: Rewrite the filters test**

In `filtering.test.tsx`, the requests mock gains a controllable `postRequest` and loses `loadJSON`:

```ts
const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  downloadJSON: vi.fn(),
  setApiBase: vi.fn(),
  apiBase: () => '',
}));
// The picker's own tests cover choosing; here it hands back the one file there is.
vi.mock('../components/FilePicker', () => ({
  FilePicker: (props: { onChange?: (v: string) => void }) =>
    <button data-pick onClick={() => props.onChange?.('filters.json')}>pick</button>,
}));
```

`beforeEach`: `postRequest.mockReset(); postRequest.mockImplementation(() => Promise.resolve([]));` in place of the `loadJSON` reset. Replace `describe('uploading filters', …)` with:

```ts
describe('loading filters', () => {
  it('replaces the store with the document, rebuilt into Intervals and Sets', async () => {
    // A filters document is plain JSON: `{min,max}` and arrays. The store holds `Interval`s and
    // `Set`s. The upload used to hand the parsed JSON straight to the store, so a categorical
    // filter arrived as an array where a `Set` was expected.
    const saved = { numerical: { TEMP: { min: 0, max: 10 } }, categorical: { cbwd: ['NW', 'SE'] } };
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'read-document' ? { valid: true, document: saved } : []));
    const { container, getByText } = render(() => <Filters />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    fireEvent.click(getByText('Load filters'));
    await waitFor(() => expect(filters.numerical.TEMP).toBeDefined());
    expect(filters.numerical.TEMP).toBeInstanceOf(Interval);
    expect(filters.numerical.TEMP?.max).toBe(10);
    expect(filters.categorical.cbwd).toBeInstanceOf(Set);
    expect([...filters.categorical.cbwd!]).toEqual(['NW', 'SE']);
  });

  it('saves the filters as plain JSON, which is what loads back', async () => {
    setFilters(() => ({ numerical: { TEMP: new Interval(0, 10) }, categorical: { cbwd: new Set(['NW']) } }));
    await flush();
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'write-document' ? { valid: true, path: 'filters.json' } : []));
    const { getByText } = render(() => <Filters />);
    fireEvent.click(getByText('Save filters'));
    await waitFor(() => expect(postRequest.mock.calls.some((c) => c[0] === 'write-document')).toBe(true));
    const sent = postRequest.mock.calls.find((c) => c[0] === 'write-document')![1] as { document: unknown };
    expect(sent.document).toEqual({ numerical: { TEMP: { min: 0, max: 10 } }, categorical: { cbwd: ['NW'] } });
  });
});
```

- [ ] **Step 2: Run, watch them fail**

```bash
npx vitest run src/left-tabs/filtering.test.tsx > /tmp/t6-red.log 2>&1; cat /tmp/t6-red.log
```
Expected: both fail — there is no `Load filters` / `Save filters`.

- [ ] **Step 3: Mount `Documents` in the Filter tab**

In `filtering.tsx`: the import `DownloadJSONButton, UploadJSONButton` becomes `import { Documents } from "../components/Documents";`; add `filtersCodec` to the `../stores` import; replace the `<div class="flex gap-2">…</div>` holding the two buttons (`:81-97`, its comment included) with:

```tsx
      {/*
        Through the codec both ways. The store holds `Interval`s and `Set`s, which are not JSON:
        a `Set` stringifies to `{}`, so the file `Download filters` used to write could not be
        loaded back, and an uploaded file reached the store as plain objects and arrays. Loading
        replaces the store wholesale (`reconcile`) rather than merging — a merge would leave
        filters the file does not mention still applied.
      */}
      <Documents
        kind="filters"
        document={() => filtersCodec.encode(state)}
        onLoad={(document) => {
          setState(reconcile(filtersCodec.decode(document)));
          return [];
        }}
      />
```

- [ ] **Step 4: Delete the browser dialog**

`components/JSON.tsx`: delete `UploadProps` and `UploadJSONButton` and the now-unused `loadJSON` import. `requests.ts`: delete `loadJSON`. In every file `git grep -ln loadJSON dashiboard-ui/src` names, delete the `loadJSON: …,` key of the requests mock (and any `const loadJSON = vi.fn()` left unused). Afterwards `git grep -n "loadJSON\|UploadJSONButton" dashiboard-ui/src` returns nothing.

- [ ] **Step 5: Run, watch them pass; full UI verification**

```bash
npx vitest run src/left-tabs/filtering.test.tsx > /tmp/t6-green.log 2>&1; cat /tmp/t6-green.log
```
then the Global Constraints' four commands.

- [ ] **Step 6: Mutation-check the codec** — make `onLoad` call `setState(reconcile(document as FiltersStore))`: the first test must FAIL on `toBeInstanceOf(Interval)`. Restore.

- [ ] **Step 7: Commit**

```bash
git add dashiboard-ui/src
git commit -m "filters: load, save and download through the codec; the browser's file dialog goes"
```

---

## Hand-over

After Task 6: the UI's four commands and the Julia suite on the final tree. Then, against a running server launched on `dashiboard-ui/smoke-test-assets` (restart it — three routes are new), through the Vite dev proxy:

```bash
curl -s -X POST -H 'content-type: application/json' --data '{}' http://127.0.0.1:3001/list-files
curl -s -X POST -H 'content-type: application/json' --data '{"path":"2-loop.json","kind":"cards"}' http://127.0.0.1:3001/read-document
curl -s -X POST -H 'content-type: application/json' --data '{"path":"../x.json","kind":"cards"}' http://127.0.0.1:3001/read-document
```
Expected: the four cards files as `cards` and `stress-250k.parquet` as `table`; the looped document under `document`; the "outside the data directory" envelope. A route missing from `vite.config.ts` answers Vite's 404 HTML here — that is the check this step exists for. The owner's browser checks are in the spec, §9.
