# Launching DashiBoard

Two processes: the Julia server (`bin/launch.jl`) and the Vite dev server for the UI
(`dashiboard-ui/`). All paths below are relative to the repository root.

## 1. The server

```sh
julia --project=DashiBoard bin/launch.jl <data_directory>
```

`<data_directory>` is the folder whose files the **Load** tab lists, e.g.
`~/Documents/Limen/agentgraph/.dashi`.

Options (`julia --project=DashiBoard bin/launch.jl --help`):

| flag | default | meaning |
|---|---|---|
| `--host` | `127.0.0.1` | address to bind |
| `--port` | `8080` | port to bind |
| `--model_directory` | `static/model` | model configuration TOMLs |
| `--training_directory` | `static/training` | training configuration TOMLs |

### Debug: the access log

The server logs one line per request — method, route, status, elapsed time — at `@debug`
level, so it is silent unless asked for:

```sh
JULIA_DEBUG=DashiBoard julia --project=DashiBoard bin/launch.jl --port 8090 <data_directory>
```

### Printing to a file

Redirect both streams; the log goes to stderr. The middleware flushes after every request,
so the file is current even though Julia block-buffers stderr when it is not a terminal:

```sh
JULIA_DEBUG=DashiBoard julia --project=DashiBoard bin/launch.jl --port 8090 <data_directory> > /tmp/dashi.log 2>&1
```

Then watch it from another shell: `tail -f /tmp/dashi.log`.

### Cache directory

The server keeps a DuckDB cache, and DuckDB allows one writer per database. To run a second
server (or the test suite) while one is already up, give it its own cache:

```sh
DASHIBOARD_CACHE=/tmp/dashi-cache-2 julia --project=DashiBoard bin/launch.jl --port 8091 <data_directory>
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
