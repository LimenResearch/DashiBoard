# Launching DashiBoard

Two processes: the Julia server (`bin/launch.jl`) and the Vite dev server for the UI
(`dashiboard-ui/`). All paths below are relative to the repository root.

## 1. The server

```sh
julia --project=DashiBoard bin/launch.jl <workspace>
```

`<workspace>` is the directory the server works in. Laid out, it looks like this:

```
<workspace>/
├── dashiboard.toml     optional
├── data/               tables: parquet, csv, json tables
├── pipeline/           pipeline documents
├── filter/             filters documents
├── model/              model configuration TOMLs
└── training/           training configuration TOMLs
```

Each folder is where the server lists, reads and saves files of that kind. A folder may hold
subfolders, under any name but the layout's own (`data`, `pipeline`, `filter`, `model`,
`training`, `quarantine`). A workspace need not be laid out: a plain folder with everything in it is served as it
is, with a warning naming the kinds that are read from the root. The workspace has to exist and
be writable: saved documents and the extensions' environment go into it.

### Sorting a plain folder

```sh
julia --project=DashiBoard bin/launch.jl <folder> --init
```

moves each loose file into its folder by what it is — a table, a pipeline or filters document, a
model or training configuration — and writes `dashiboard.toml` when there is none. When there is
one, the folders it names under `[directories]` are the ones used. What cannot be placed (a file
of no known kind, a folder that is not the layout's, a name already taken where the file belongs)
goes to `quarantine/`, which the server ignores, and the report says why. It exits without
serving.

It moves everything at the top of the folder, so it refuses a folder that is plainly something
else: a home directory, or one holding a `Project.toml`, `Manifest.toml`, `package.json`,
`Cargo.toml` or `pyproject.toml`. Hidden files and links are left where they are.

### `dashiboard.toml`

Every entry is optional; a flag overrides the file. A table or an entry the launcher does not
know, or a value of the wrong kind, stops the launch by name. The server never writes this file,
and refuses a request to: it names packages the launcher installs and loads.

```toml
[directories]            # relative to this file, or absolute; absent = the folder, else the root
data = "data"
pipeline = "pipeline"
filter = "filter"
model = "model"
training = "training"

[extensions]             # each installed extension and where it is, as Julia's [sources] says it
StreamlinerExtras = { path = "/opt/limen/StreamlinerExtras.jl" }
TimeFunnels = { url = "https://github.com/LimenResearch/TimeFunnels.jl", rev = "main" }

[server]
host = "127.0.0.1"
port = 8080
```

### Extensions

The server registers nothing beyond DashiBoard's own cards, funnels and transforms unless the
workspace names extensions. With extensions the launch has two stages. The first builds one Julia
environment under `<workspace>/.dashiboard/env/`, holding this checkout's own packages and each
extension from the source given, resolved together. The second is the server itself, started
inside that environment, so every package it loads is the version that was resolved with the
extensions; stopping the launcher stops it.

The environment is built when the sources change — the table, or the project file of anything
taken by path — which takes minutes; a launch with unchanged sources reuses it. An extension that
cannot be resolved stops the launch, naming it. Deleting `.dashiboard/env/` forces a rebuild.

An extension is a package that exposes `DEFAULT_PARSER`, a `StreamlinerCore.Parser` holding what
it registers. A source is a `path`, or a `url` with an optional `rev`.

A `path` in the table is relative to the workspace. On the command line:
`--extensions Name=/path/to/Package,Other=https://host/Other.jl@main`, which replaces the file's
table; a relative path there is relative to where the command is run, and `@rev` may be left out.

Options (`julia --project=DashiBoard bin/launch.jl --help`):

| flag | default | meaning |
|---|---|---|
| `--host` | the file's, else `127.0.0.1` | address to bind |
| `--port` | the file's, else `8080` | port to bind |
| `--data_dir` | see below | tables |
| `--pipeline_dir` | see below | pipeline documents |
| `--filter_dir` | see below | filters documents |
| `--model_dir` | see below | model configuration TOMLs |
| `--training_dir` | see below | training configuration TOMLs |
| `--extensions` | the file's | extensions to register |
| `--init` | | sort the folder into the layout and exit |

Each directory is, in this order: the flag; the file's `[directories]` entry; the folder of that
name in the workspace (`data`, `pipeline`, `filter`, `model`, `training`) when it exists; the
workspace itself. A relative flag is relative to where the command is run, a relative entry of the
file to the workspace. A directory that a flag or the file names and that does not exist stops the
launch.

The repository keeps sample configurations in `static/model` and `static/training`. To use them
with a workspace that has none of its own, from the repository root:

```sh
julia --project=DashiBoard bin/launch.jl <workspace> --model_dir static/model --training_dir static/training
```

### Debug: the access log

The server logs one line per request — method, route, status, elapsed time — at `@debug`
level, so it is silent unless asked for:

```sh
JULIA_DEBUG=DashiBoard julia --project=DashiBoard bin/launch.jl --port 8090 <workspace>
```

### Printing to a file

Redirect both streams; the log goes to stderr. The middleware flushes after every request,
so the file is current even though Julia block-buffers stderr when it is not a terminal:

```sh
JULIA_DEBUG=DashiBoard julia --project=DashiBoard bin/launch.jl --port 8090 <workspace> > /tmp/dashi.log 2>&1
```

Then watch it from another shell: `tail -f /tmp/dashi.log`.

### Cache directory

The server keeps a DuckDB cache, and DuckDB allows one writer per database. To run a second
server (or the test suite) while one is already up, give it its own cache:

```sh
DASHIBOARD_CACHE=/tmp/dashi-cache-2 julia --project=DashiBoard bin/launch.jl --port 8091 <workspace>
```

## 2. The UI

The UI is a **pnpm** project (`pnpm-lock.yaml`). Do not use `npm install` — npm cannot read
pnpm's `node_modules` layout and fails with `Cannot read properties of null (reading 'matches')`.

```sh
cd dashiboard-ui
pnpm install       # first time only, or after pulling a lockfile change
pnpm run dev       # http://localhost:3000
```

Vite proxies the API routes to the server. The default target is `http://127.0.0.1:8080`;
point it elsewhere with `DASHI_API`:

```sh
DASHI_API=http://127.0.0.1:8090 pnpm run dev
```

Page-URL keys (read once at load):

| key | example | effect |
|---|---|---|
| `?api=` | `http://localhost:3000/?api=http://127.0.0.1:8090` | talk to that server directly, bypassing the proxy |
| `?tab=` | `http://localhost:3000/?tab=process` | open on that section (`load`, `filter`, `process`, `document`); absent → the last one used |
| `?theme=` | `http://localhost:3000/?theme=dark` | colour scheme |

## 3. A typical session

```sh
# shell 1 — server with the access log on file
JULIA_DEBUG=DashiBoard julia --project=DashiBoard bin/launch.jl --port 8090 ~/Documents/Limen/agentgraph/.dashi > /tmp/dashi.log 2>&1

# shell 2 — UI against it
cd dashiboard-ui && DASHI_API=http://127.0.0.1:8090 pnpm run dev

# shell 3 — watch the requests
tail -f /tmp/dashi.log
```

## 4. Checks

```sh
# UI, from dashiboard-ui/
pnpm exec vitest run --reporter=dot && pnpm exec tsc --noEmit && pnpm run lint && pnpm run build

# Julia, from the repository root — its own cache, so a running server does not block it
DASHIBOARD_CACHE=/tmp/dashi-test julia --project=DashiBoard/test DashiBoard/test/runtests.jl
```
