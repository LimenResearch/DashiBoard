# Prompt — ExperimentTracking.jl session

Launch in `/home/dariosarra/Documents/Limen/ExperimentTracking.jl`. Paste everything below
the line.

---

You are the resident expert on this repository (ExperimentTracking.jl) for a four-repository
design exercise. The lead session is in /home/dariosarra/Documents/Limen/DashiBoard; the
others are in /home/dariosarra/Documents/Limen/agentgraph and
/home/dariosarra/Documents/Limen/nexus-weaver-pro. They will message you.

READ FIRST, in this order:
  /home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/README.md
  /home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/00-dashiboard-context.md
  /home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/01-decisions.md
  /home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/02-stack.md

`01-decisions.md` is the specification and is binding. If your findings contradict it, say so
explicitly and give your reason — do not quietly work around it. Its section 12 lists what is
still open; those are the questions your brief exists to answer.

READ-ONLY **for now**: do not modify, refactor or commit anything in this repository during
reconnaissance. But changes to THIS repository are in scope for the refactor (section 1) —
where a change here is the right answer, recommend it in your brief with enough detail to act
on. You are not a fixed constraint to be designed around.

BRANCH SETUP — do this before anything else, including reading:

    git status                              # tree must be clean
    git checkout main
    git pull --ff-only
    git checkout --no-track -b ds-DashiUI

`--no-track` is deliberate: `main` is unprotected on these repositories, and a tracking
branch makes git's suggested push land on main. If `ds-DashiUI` already exists, switch to it
rather than recreating it. If the tree is dirty, or the pull is not a fast-forward, STOP and
report it — do not stash, merge or rebase to get past it.

This branch is where implementation lands later. Reconnaissance itself stays read-only; the
branch exists so that when work starts there is somewhere for it to go, on the same name in
all four repositories.

You matter most of the four. The decided design has the UI emit an ExperimentTracking
`Config`, run via your API, and be served as static assets by your HTTP server. Your `cards`
and `schema` methods are already most of the API the refactor needs. Much of this may be a
question of what you already do rather than what needs building — and where it is not, the
work lands here.

Answer, citing `ExperimentTracking:path:LINE` for every claim:

1. Config, DataFlow and the registry. Document `Config`, `DataFlow`, `Run`, `Result` and
   `Entry` precisely: every field, its type, how it is serialised, and how a config TOML is
   parsed into them. Confirm that `Config` is exactly what the UI should emit and that it
   carries no DataFlow.
2. Serving the UI. Decision section 10 has your HTTP server serving the frontend's static
   assets alongside `POST api/v1`, so that app and API share an origin. What does that take
   in `api/router.jl` — a static file route, a fallback for client-side routing, cache
   headers, a build-output location? Any reason it is a bad idea?
3. The five orphaned capabilities. `get-acceptable-paths`, `load-files`, `fetch-data`,
   `get-processed-data` and Graphviz DOT rendering exist only on the DashiBoard server
   (see 02-stack.md) and the new UI needs all five. For each: should it move here, and what
   would it cost? Then answer the question that follows from it — should the `DashiBoard`
   package survive as a server at all? Argue it, including the case against.
4. The schema dialect gap. `schema_handler` passes `vars::Vector{String}`, reaching the flat
   `schema_definitions(::AbstractVector)` rather than the `VariableConfig` method in Pipelines'
   group_api. Confirm this. Decision section 6 requires group-vocabulary schemas. What is the
   change — new parameters, a new method, breaking for existing callers? Who calls `schema`
   today? Note that AgentGraph's `discover()` calls only `cards`.
5. Filters. Decision section 8 keeps `filters` as a top-level key of `Config`, unified in the
   canvas UI but unchanged in the document, on the grounds that this costs no schema change and
   no registry migration. Confirm that is right. Are `DataIngestion.Filter` types annotated
   structs from which UI can be derived the same way cards are? Is `Config.filters` read
   anywhere outside `run_pipeline`?
6. The JSON-RPC surface in full. Every method, its params and result shape, its error codes,
   and the request-validation split described in the `parse_execute_params` docstring. Include
   the `run_id` progress mechanism and what a client receives. Confirm for the record that the
   envelope's version field is `version` and not `jsonrpc`, and say whether that is deliberate.
7. Multi-pipeline orchestration. Your stated purpose, which the lead session has not read. How
   are several pipelines over one source expressed, scheduled and related? What does
   `Run.from` mean operationally? Decision section 9 has you building capabilities on top of
   DashiBoard's UI — what are they concretely, and what would they need from it?
8. Source connection and artifacts. What can a `DataFlow` source be — a file, a DuckDB table,
   a Postgres connection? One per config or several? What must a UI collect to produce a valid
   DataFlow, and what can it validate before running? Document the parquet exchange
   (`COPY ... TO`) that AgentGraph's artifact_codecs says both ends use.
9. What the decisions cost you. Read `01-decisions.md` in full and state concretely which
   sections imply work here and how much.

Write your brief to (create nothing else, edit nothing else):
/home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/15-experimenttracking-brief.md

Then stay available for follow-up questions.
