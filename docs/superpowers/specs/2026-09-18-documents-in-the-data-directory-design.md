# Documents in the data directory — one visibility for tables and documents

Why: the two ways files enter the UI are inconsistent. `Choose files` asks the server, which lists
the supported tables under its data directory as relative paths — the file never reaches the
browser. `Upload cards` and `Upload filters` are the browser's own file dialog: the file is read
on the user's machine and the server never sees it, so the dialog shows the whole disk. Decided
with the owner on 2026-09-18: **documents (cards, filters) are listed, read and written by the
server inside its data directory, through the same picker tables use, filtered by kind; the
browser dialog goes.** Further decisions the same day: a `.json` is told apart from a table **by
content**; navigation is the **flat list of relative paths** the picker already shows; **JSON and
TOML** documents are accepted; **replacing** on load stays (no merge); and the save path, the
filters codec and the path check are folded in rather than parked. Baseline: `ds-DashiUI` @
`6ab1398`. `DashiBoard/src` and `dashiboard-ui/` change; `Pipelines/` and `DataIngestion/` do
not (the team leader is in Pipelines).

## 1. Listing: `POST /list-files` → `[{path, kind}]`

Replaces `get-acceptable-paths` (its only caller is `FilePicker`). The server walks
`DataIngestion.DATA_DIR[]` as `acceptable_paths` does — every file, relative path, subfolders
included, hidden entries skipped — and classifies each:

| extension | kind |
|---|---|
| parquet, csv, tsv, txt (`DataIngestion.is_supported`) | `table` |
| json | parsed and peeked: an object with `nodes` and `groups` → `cards`; with `numerical` and `categorical` → `filters`; anything else → `table` (`json_reader` still reads it) |
| toml | parsed and peeked the same way → `cards` or `filters`; anything else → not listed |
| other | not listed |

A file that does not parse is not listed: a half-written document cannot break the listing, and
the listing is not where a parse error is reported (§2 is). The peek parses the whole file; a
document is small and a JSON table is rare, so this costs nothing that matters, and it is what
makes the kind survive a rename. A missing data directory answers `[]` with a logged warning
rather than a 500 — today `walkdir` throws and the log still prints 200 (middleware.jl:64–67).

Where: `DashiBoard/src/handlers.jl`, `list_files`, registered in `launch.jl`. The walk is
DashiBoard's own over `DATA_DIR[]`; the kind of a document is DashiBoard's concept, not
DataIngestion's.

## 2. Reading: `POST /read-document {path, kind}` → the document

Resolves `path` under the data directory with the one path function of §5, parses JSON or TOML
by extension, checks the shape matches `kind` (the same test as §1), and answers
`{valid:true, document}` — wrapped, so a reply is told from a failure by `valid` alone and never
by guessing at a document's keys.
Failure — an escaping path, a missing file, a parse error, the wrong kind — answers
`failure_report("document", exception)`: `{valid:false, kind:"document", errors:[…], issues:[]}`,
the envelope every other route uses, so the client shows the server's sentence.

The client then does what an upload does today, with two changes. Cards: `uploadCards` in
`processing.tsx` (renamed `loadCards`; the snapshot it probes is the document the server
returned). Filters: through `filtersCodec.decode` before `setState(reconcile(...))` — today the
upload hands raw JSON to the store, so a categorical filter arrives as an array where the store
holds a `Set`, and an interval as a plain object where it holds an `Interval`.

## 3. Writing: `POST /write-document {path, kind, document, overwrite}`

The counterpart of §2, so a document round-trips inside the data directory: `Download` puts a
file in the browser's download folder, from where it has to be moved by hand to be loadable
again. The server resolves `path` (§5), refuses a kind mismatch (the same shape test), refuses an
existing file unless `overwrite` is `true`, writes JSON (`JSON.json` with indentation; TOML is
read, not written; the name must end in `.json`), and answers `{valid:true, path}` or the failure
envelope. The directory of `path` must
exist: the server creates no folders.

The browser `Download` stays: it costs nothing and it is the way to get a document off a server
one does not have a shell on. It changes in one way: it writes exactly the bytes `Save` writes —
the encoded document (`filtersCodec.encode`; cards need none) — so the downloaded filters file
is loadable. Today `Download filters` serialises the live store, and a `Set` stringifies to `{}`.

## 4. The UI: one `Documents` bar per kind

`FilePicker` gains `kind: "table" | "cards" | "filters"`, asks `list-files`, and offers the paths
of that kind. It keeps its refresh button and its shape; the Load tab uses `kind="table"`
exactly as now.

A new `components/Documents.tsx`, mounted in the Process tab with `kind="cards"` and in the
Filter tab with `kind="filters"`, holds the whole document row and replaces the two
`Download`/`Upload` pairs. Left to right:

- `FilePicker kind={kind}` (single choice) and a **Load cards** / **Load filters** button, which
  posts `read-document` and hands the answer to the kind's loader. "Load", not "Upload": nothing
  is uploaded any more.
- An `Input` for a file name (default `cards.json` / `filters.json`), a `Checkbox` "replace an
  existing file", and a **Save cards** / **Save filters** button, which posts `write-document`
  with the encoded document; on success the picker refreshes so the new file is listed.
- **Download cards** / **Download filters**, the existing `DownloadJSONButton`, given the encoded
  document.
- One error block, `[data-document-error]`, in the dress a failed run's text wears, for two
  sources: the failure envelope of a load or a save, and whatever the loader could not place —
  the sentences `uploadCards` shows under the buttons today (`[data-upload-error]`, which moves
  here). Cleared by the next load or save, and by the next edit of the document.

Reused as they are: `FilePicker`, `Button`, `Input`, `Checkbox`, `DownloadJSONButton`. Deleted:
`UploadJSONButton` (`components/JSON.tsx`) and `loadJSON` (`requests.ts`), with their tests. The
loaders stay where they are: `loadCards` in `processing.tsx` (it owns the probe wiring), the
filters loader in `filtering.tsx`. `Documents` knows nothing of either store; its props are
`kind`, `document()` — the encoded document, to save or download — and
`onLoad(document): Promise<string[]>`, the sentences the loader could not place (empty when all
was placed). "The document changed since" is `document()` having changed, which is what clears
the block, so the `CARDS_JSON` comparison `uploadCards` keeps today moves into `Documents` as a
comparison of `document()`.

## 5. Paths: one function, three callers

`resolve_in_data_dir(path)` in `handlers.jl`: normalises `joinpath(DATA_DIR[], path)` and throws
`ArgumentError("`$path` is outside the data directory")` unless the result starts with the
normalised data directory; an absolute `path` is refused the same way. Used by `read-document`,
`write-document`, and — in passing — by the `load-files` handler before it hands paths to
`DataIngestion.load_files`, which today joins `..` without looking. `DataIngestion.parse_paths`
is not touched.

## 6. What the screen shows

| action | before | after |
|---|---|---|
| Choose files | tables under the data directory | same, from `list-files` filtered to `table` |
| Load cards / filters | browser dialog over the whole disk, JSON only | picker over the data directory, `cards` / `filters` only, JSON and TOML |
| Save cards / filters | — | a name, a replace checkbox, a file in the data directory, picker refreshed |
| Download | live store serialised (filters broken) | the encoded document (loadable) |
| a load or save that fails | silent (`loadJSON` logs to the console) | the server's sentence under the buttons |
| a data directory that does not exist | 500 logged as 200, empty picker | `[]`, a warning in the log |

## 7. Tests

Server, `DashiBoard/test/dashiboard.jl`, against a temporary data directory built by the test
(a parquet, a csv, `cards.json`, `cards.toml`, `filters.json`, a `sub/table.json` that is a
real JSON table, a `broken.json`, a hidden `.x.json`):
- `list-files`: exactly those, with the right kinds; `broken.json` and `.x.json` absent;
  `sub/table.json` a `table`.
- `read-document`: `cards.json` and `cards.toml` answer the same object; `filters.json` with
  `kind:"cards"` → the failure envelope naming the mismatch; `../x.json` and an absolute path →
  the envelope, outside the directory; a missing file → the envelope.
- `write-document`: creates a file the next `list-files` shows as the right kind; refuses an
  existing file without `overwrite`, replaces it with; refuses `..`; refuses a document of the
  wrong shape for `kind`.
- `load-files` with a `../` path → the failure envelope, not a read.
- A missing data directory: `list-files` → `[]`.

UI, `FilePicker.test.tsx`: `kind` filters the listing; the refresh button re-asks
`list-files`. `Documents.test.tsx`: Load posts `read-document` with the picked path and calls
`onLoad` with the answer; a failure envelope shows its sentence and calls nothing; Save posts
`write-document` with the name, the kind, `document()` and the checkbox, then refreshes the
picker; Download gets `document()`. `filtering.test.tsx` (or the store's): a loaded filters
document holds `Interval`s and `Set`s. `processing.test.tsx`: the upload tests of 2026-09-18
become load tests — the same four scenarios, entered through `Documents`' Load rather than a
file input.

## 8. Out of scope

A folder tree (decided: the flat relative-path list), merging a loaded document into the current
one (decided: replace), writing TOML, creating folders on save, and any change to `DataIngestion`
or `Pipelines`.

## 9. Process

`DashiBoard/src` and `dashiboard-ui/` only. Every Julia change carries its functional reason in
a docstring or comment (owner's rule, 2026-09-16). TDD both sides: the DashiBoard request tests
run against the temporary directory; the UI in jsdom. Suite, `tsc`, lint and build clean before
hand-over; one commit per task on a side branch; the owner reviews and merges. Owner's browser
checks: the Process tab lists only the four cards files and `stress-250k.parquet` is not among
them; loading `2-loop.json` behaves as check B; saving as `mine.json` and pressing `↻` lists it;
saving again without the checkbox is refused with the sentence; `Download filters` after loading
a saved filters file round-trips.
