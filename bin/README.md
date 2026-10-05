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
subfolders. A workspace need not be laid out: a plain folder with everything in it is served as it
is, with a warning naming the kinds that are read from the root.

### Sorting a plain folder

```sh
julia --project=DashiBoard bin/launch.jl <folder> --init
```

moves each loose file into its folder by what it is — a table, a pipeline or filters document, a
model or training configuration — and writes `dashiboard.toml`. What it cannot place (a file of no
known kind, a folder that is not the layout's, a name already taken where the file belongs) goes
to `quarantine/`, which the server ignores, and the report says why. It exits without serving.

### `dashiboard.toml`

Every entry is optional; a flag overrides the file.

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
workspace names extensions. For each one the launcher keeps a Julia environment under
`<workspace>/.dashiboard/env/`, built from the sources given and instantiated when they change
— the first launch with a new extension takes minutes; later ones do not — and loads the package
from it. An extension that cannot be resolved stops the launch, naming it. On the command line:
`--extensions Name=/path/to/Package,Other=https://host/Other.jl@main`, which replaces the file's
table.

Options (`julia --project=DashiBoard bin/launch.jl --help`):

| flag | default | meaning |
|---|---|---|
| `--host` | the file's, else `127.0.0.1` | address to bind |
| `--port` | the file's, else `8080` | port to bind |
| `--data_dir` | `<workspace>/data` | tables |
| `--pipeline_dir` | `<workspace>/pipeline` | pipeline documents |
| `--filter_dir` | `<workspace>/filter` | filters documents |
| `--model_dir` | `<workspace>/model` | model configuration TOMLs |
| `--training_dir` | `<workspace>/training` | training configuration TOMLs |
| `--extensions` | the file's | extensions to register |
| `--init` | | sort the folder into the layout and exit |

The repository's own `static/model` and `static/training` are not defaults any more: name them
with `--model_dir static/model --training_dir static/training` when serving a folder that has none.

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
