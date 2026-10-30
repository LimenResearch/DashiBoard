# Running DashiBoard

Two processes: the Julia server and the Vite dev server for the UI (`dashiboard-ui/`). A client's
server runs from a **deployment**, installed once; while developing, the server runs straight
from this checkout. All paths below are relative to the repository root.

## 1. The server

### A deployment

A deployment is a folder whose `dashiboard.toml` says everything it needs: which DashiBoard,
which extensions, where the files are, which port. Installing it resolves those once; launching
it never resolves, so a new release reaches a client only when an update is run on purpose.

```toml
[dashiboard]             # the release to deploy: a tag or a commit
url = "https://github.com/LimenResearch/DashiBoard"
rev = "v2.0.0"

[extensions]             # each pinned the same way; a `path` is refused
TimeFunnels = { url = "https://github.com/LimenResearch/TimeFunnels.jl", rev = "v1.0.0" }

[server]                 # read at every launch
host = "127.0.0.1"
port = 8080

[directories]            # optional; relative to this file, or absolute
data = "data"
```

`bin/install.jl` needs only Julia and git, so copy it alone to the machine:

```sh
julia install.jl <deploy>                       # install
<deploy>/.dashiboard/launch.sh                  # launch, as often as needed
julia install.jl <deploy> --update all          # after editing [dashiboard] rev: everything re-resolved
julia install.jl <deploy> --update extensions   # only the extensions move
```

Install clones DashiBoard at `rev` — the whole repository, the UI and `static/` included —
resolves it with the extensions, precompiles, sorts any loose files into the layout, and writes:

```
<deploy>/
├── dashiboard.toml
├── data/ pipeline/ filter/ model/ training/    the layout; quarantine/ holds what could not be placed
└── .dashiboard/
    ├── DashiBoard/       the clone, owned by install
    ├── Project.toml      DashiBoard, its own packages, the extensions
    ├── Manifest.toml     the resolution, fixed until an update
    ├── depot/            the deployment's own packages and compiled cache
    ├── serve.jl          loads DashiBoard and the resolved extensions, then serves
    ├── launch.sh         runs serve.jl with this project, depot and Julia
    └── record.toml       what was resolved
```

A launch reads `[server]` and `[directories]` afresh. It refuses to start when `[dashiboard]` or
`[extensions]` changed since install, when the clone is not at the commit installed, or when Julia
is not the one install ran with, and it says which update to run. Install refuses a folder that is
already installed. An extension is a package that exposes `DEFAULT_PARSER`, a
`StreamlinerCore.Parser` holding what it registers.

The log goes to stderr and is flushed after every record, so a log redirected to a file is current
while the server runs: `<deploy>/.dashiboard/launch.sh > /tmp/dashi.log 2>&1`.

### From this checkout, while developing

```sh
julia --project=DashiBoard -e 'using DashiBoard; DashiBoard.launch("<workspace>"; port = 8080)'
```

`launch` takes the directories (`data_dir`, `pipeline_dir`, `filter_dir`, `model_dir`,
`training_dir`) as keywords; each defaults to the workspace itself. The repository keeps sample
configurations in `static/model` and `static/training`. To sort a plain folder into the layout:
`julia --project=DashiBoard -e 'using DashiBoard; DashiBoard.init_workspace("<folder>")'`.

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
