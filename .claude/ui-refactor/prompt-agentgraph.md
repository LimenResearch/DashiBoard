# Prompt — AgentGraph session

Launch in `/home/dariosarra/Documents/Limen/agentgraph`. Paste everything below the line.

---

You are the resident expert on this repository (AgentGraph) for a four-repository design
exercise. The lead session is in /home/dariosarra/Documents/Limen/DashiBoard; the others are
in /home/dariosarra/Documents/Limen/ExperimentTracking.jl and
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

Two things about why you are here.

Your `core/schema/` layer says it is "Modeled on DashiBoard/Pipelines" — NODE_SPECS mirroring
CARD_SPECS, JSON Schemas derived from typed models and never hand-written, a `SchemaContext`
injecting contextual enums at generation time, one derived schema serving the designer LLM,
validation and the UI alike. That is the refactor DashiBoard is about to attempt, already
built, in Python, from DashiBoard's own pattern. **An honest account of how that went is your
most valuable contribution.**

And you own the integration point. The UI's product is a config artifact your nodes load as
`pipeline_artifact`. Note that your graph and DashiBoard's graph are never unified: DashiBoard
is one step inside one of your nodes, and that step's internal DAG is opaque to you.

Answer, citing `agentgraph:path:LINE` for every claim:

1. THE SCHEMA LAYER. Walk through `core/schema/` in detail: how NODE_SPECS registers a node
   type, how `derive.py` composes per-type schemas into a discriminated union, how
   `SchemaContext` injects enums, and what `GET /v1/graphs/schema` returns — paste a real
   example. Then, candidly: which parts of this design have worked and which have caused pain?
   What does the derivation fail to express, and what did you work around? Where does
   presentation metadata come from, and is that adequate? DashiBoard has decided on JSON
   Schema's own `title`/`description` with widget kind inferred and no override (section 4) —
   say whether that would have been enough for you.
2. Nesting depth. Decision section 3 makes a card's UI a pure recursive tree derived from type
   structure with NO ambient scope: a component must be renderable from its type alone, three
   or four levels deep, with cross-level constraints demoted to validation errors. Do your
   derived schemas nest that far? Have you hit a case where a nested field needed something
   from an ancestor, and what did you do?
3. THE CONFIG ARTIFACT LIFECYCLE. Document the full lifecycle of a `pipeline_artifact`: how a
   structured_data artifact is created and registered, how uuid-versus-alias resolution works,
   how `ConfigInput` merges its fields with explicit parameters, and what
   `content_metadata["required_columns"]` is — who writes it and when. Then, concretely: if a
   DashiBoard authoring UI wants to SAVE a `{nodes, groups, filters}` config as an artifact
   your nodes can reference, what must it call, with what payload, and what does it get back?
   Can that be done from a browser, and with what auth?
4. The services layer as an embedding mechanism. Decision section 9 has nexus-weaver-pro
   embedding the DashiBoard UI through the `RemoteService` connection you already define, on
   the understanding that `routes_services.py` carries the URL but not the traffic — the only
   call you make on that connection is `discover()`. Confirm or correct that. Would you want
   nexus talking to ExperimentTracking directly, or should something proxy through you? What
   would each cost you?
5. The wire, as built. Document `tools/remote_procedure.py` and `tools/platform/dashiboard.py`
   exactly: the envelope (including `version` rather than `jsonrpc`), which RPC methods you
   call, connection resolution and the DASHIBOARD_URL/DASHIBOARD_TIMEOUT variables, the
   probe/discover path, payload validation, preflight column checks, error surfacing, and the
   parquet exchange in `artifact_codecs.py`. Then: what do you WISH that API gave you and does
   not?
6. Graph declaration. The exact YAML schema: the node record, how a node declares what it
   consumes, and how the loader infers edges from that. Quote a real config. DashiBoard infers
   edges the same way — note where the two models agree and differ, especially around anything
   resembling its groups and `through` qualifier.
7. Validation, errors and streaming. How a config is validated and the exact error shape a UI
   receives. How the Dolt "latest valid version" rule surfaces to a client. The Redis-backed
   streaming contract and `/v1/executions/{id}/stream`.
8. Anything in your codebase that assumes your graph and DashiBoard's are the same kind of
   thing. Flag it.

Write your brief to (create nothing else, edit nothing else):
/home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/10-agentgraph-brief.md

Then stay available for follow-up questions.
