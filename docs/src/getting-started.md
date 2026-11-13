# Getting Started

DashiBoard is still in development, thus installing requires a few passages.

They include two processes: the Julia server and the Vite dev server for the UI (`dashiboard-ui/`).

## Installation dependencies

- Julia programming language (minimum version 1.12, installable via [juliaup](https://github.com/JuliaLang/juliaup)).
- JavaScript package manager [pnpm](https://pnpm.io/).

## Launching the server

Open a terminal at the top-level of the repository.

Install all required dependencies with the following command:

```
julia --project=DashiBoard -e 'using Pkg; Pkg.instantiate()'
```

Then, launch the server with the following command:

```
julia --project=DashiBoard -e 'using DashiBoard; ws = "path/to/workspace"; DashiBoard.launch(ws; data_dir = joinpath(ws, "data"), pipeline_dir = joinpath(ws, "pipeline"), filter_dir = joinpath(ws, "filter"), model_dir = joinpath(ws, "model"), training_dir = joinpath(ws, "training"))'
```

where `path/to/workspace` is the folder DashiBoard works in: its tables in `data/`, saved
pipelines in `pipeline/`, filters in `filter/`, model and training configurations in `model/`
and `training/`, as the keywords name them (each defaults to the workspace itself).

### Configuring server via TOML

A workspace is a folder whose `dashiboard.toml` says everything it needs.

```toml
[extensions]
SomeExtension = { is_plugin = true }

[server]
host = "127.0.0.1"
port = 8080

[directories]            # optional; relative to this file, or absolute
data = "data"
```

The server can then be started with a standard `launch.jl` script:

```julia
using DashiBoard: DashiBoard

const WORKSPACE = @__DIR__
const CONFIG = DashiBoard.read_workspace_file(WORKSPACE)
DashiBoard.init_workspace(WORKSPACE, CONFIG)

module Extensions
    for ext in keys(parentmodule(@__MODULE__).CONFIG.extensions)
        @eval using $(Symbol(ext)): $(Symbol(ext))
    end
end

DashiBoard.launch(Extensions, WORKSPACE, CONFIG; async = false)
```

```sh
julia launch.jl
```

Folder structure:

```
<deploy>/
├── launch.jl
├── dashiboard.toml
└── data/ pipeline/ filter/ model/ training/
```

### Cache directory

The server keeps a DuckDB cache, and DuckDB allows one writer per database. To run a second
server (or the test suite) while one is already up, give it its own cache with
`DASHIBOARD_CACHE=/tmp/dashi-cache-2`.

## Launching the frontend

Open a terminal in the `dashiboard-ui` folder.

Install all required dependencies with the following command:

```
pnpm install
```

Then, launch the frontend with the following command:

```
pnpm run start
```

To interact with the UI, open your browser and navigate to the page [http://localhost:3000](http://localhost:3000).

The dev server proxies the Julia API, so the page and the API share an origin exactly as they will
when the bundle is served alongside the server.

### Frontend details

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

## A typical session

```sh
# shell 1 — the server, its log on file
julia --project=DashiBoard -e 'using DashiBoard; DashiBoard.launch("<workspace>"; port = 8090)' > /tmp/dashi.log 2>&1

# shell 2 — UI against it
cd dashiboard-ui && DASHI_API=http://127.0.0.1:8090 pnpm run dev

# shell 3 — watch the log
tail -f /tmp/dashi.log
```

### Checks

```sh
# UI, from dashiboard-ui/
pnpm exec vitest run --reporter=dot && pnpm exec tsc --noEmit && pnpm run lint && pnpm run build

# Julia, from the repository root — its own cache, so a running server does not block it
DASHIBOARD_CACHE=/tmp/dashi-test julia --project=DashiBoard/test DashiBoard/test/runtests.jl
```
