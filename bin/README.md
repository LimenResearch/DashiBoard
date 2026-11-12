# Running DashiBoard

Two processes: the Julia server and the Vite dev server for the UI (`dashiboard-ui/`).
All paths below are relative to the repository root.

## 1. The server

### A deployment

A deployment is a folder whose `dashiboard.toml` says everything it needs.

```toml
[extensions]             # each pinned the same way; a `path` is refused
SomeExtension = { is_plugin = true }

[server]                 # read at every launch
host = "127.0.0.1"
port = 8080

[directories]            # optional; relative to this file, or absolute
data = "data"
```

`bin/install.jl` needs only Julia and git, so copy it alone to the machine:

```sh
julia launch.jl
```

```
<deploy>/
├── dashiboard.toml
└── data/ pipeline/ filter/ model/ training/
```

### Cache directory

The server keeps a DuckDB cache, and DuckDB allows one writer per database. To run a second
server (or the test suite) while one is already up, give it its own cache with
`DASHIBOARD_CACHE=/tmp/dashi-cache-2`.

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
# shell 1 — the server, its log on file
julia --project=DashiBoard -e 'using DashiBoard; DashiBoard.launch("<workspace>"; port = 8090)' > /tmp/dashi.log 2>&1

# shell 2 — UI against it
cd dashiboard-ui && DASHI_API=http://127.0.0.1:8090 pnpm run dev

# shell 3 — watch the log
tail -f /tmp/dashi.log
```

## 4. Checks

```sh
# UI, from dashiboard-ui/
pnpm exec vitest run --reporter=dot && pnpm exec tsc --noEmit && pnpm run lint && pnpm run build

# Julia, from the repository root — its own cache, so a running server does not block it
DASHIBOARD_CACHE=/tmp/dashi-test julia --project=DashiBoard/test DashiBoard/test/runtests.jl
```
