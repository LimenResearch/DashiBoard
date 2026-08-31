# Prompt — nexus-weaver-pro session

Launch in `/home/dariosarra/Documents/Limen/nexus-weaver-pro`. Paste everything below the
line.

---

You are the resident expert on this repository (nexus-weaver-pro) for a four-repository design
exercise. The lead session is in /home/dariosarra/Documents/Limen/DashiBoard; the others are
in /home/dariosarra/Documents/Limen/agentgraph and
/home/dariosarra/Documents/Limen/ExperimentTracking.jl. They will message you.

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

Three things to have straight before you answer anything.

**You are a host, not the owner.** DashiBoard builds and serves its own UI; it runs standalone
as its primary mode and is additionally embedded here, replacing the mocked
`src/pages/DashiboardPage.tsx` at /dashiboard. The question is not how nexus-weaver-pro should
build a DashiBoard page — it is what contract an externally built, externally served UI must
satisfy to sit inside this app.

**Your placeholder's interaction model does not survive.** Decision section 5 makes the canvas
an auto-laid-out DAG with a side editing panel and no stored node positions, because edges are
INFERRED from what each node consumes and a user can never draw one. `PipelineConnection`, the
`layer` field, connection-drawing and `GraphMinimap` have no counterpart. Do not design around
them; tell the lead session what in this app depends on them.

**The UI's product is a config artifact.** It authors a `{nodes, groups, filters}` document
which a user loads into an AgentGraph node as that node's `pipeline_artifact`. Your
`dashiboardPipelineId` is that artifact reference. What crosses the host boundary is one
config document each way — not a live data stream. AgentGraph's graph and DashiBoard's graph
are never unified; do not propose it.

Answer, citing `nexus-weaver-pro:path:LINE` for every claim:

1. What the placeholder commits you to. Inventory `DashiboardPage.tsx`: every affordance,
   every piece of state, the invented data model, the execution simulation. For each, say
   whether it is design intent the real UI must honour, or filler to discard. Where the code
   cannot tell you, say who would know.
2. THE EMBEDDING CONTRACT. Enumerate the mechanisms by which an externally owned, externally
   served UI could occupy /dashiboard: iframe with postMessage, an npm package exporting a
   React component, Module Federation, a web component, a build-time vendored bundle. For each,
   what breaks and what it costs in THIS codebase. Cover at minimum: react-router and the
   `?pipeline=` query parameter, AppLayout chrome and the assistant side panel
   (`src/components/AppLayout.tsx` registers per-route summaries), Tailwind and shadcn
   CSS-variable theming, next-themes dark mode, fonts and assets, CSP, and whether the embedded
   UI can share auth or session. End with a recommendation and your reasoning.
   Weigh it knowing two things: the boundary payload is one config document each way; and
   ExperimentTracking will serve the UI's assets, so an iframe pointed at the resolved
   RemoteService URL is same-origin inside the frame, whereas a React component compiled into
   your build runs on YOUR origin and needs CORS on the Julia side regardless.
   **This answer decides DashiBoard's frontend framework** — a React component means its
   standalone UI is React too; an iframe leaves the framework free. Say which way you point and
   confirm you understand that consequence.
3. Design tokens. What must an embedded UI honour to look native — the CSS custom properties,
   the `tailwind.config.ts` theme extension, radius and spacing conventions, and where
   `components/ui` ends and app code begins.
4. Schema-driven forms, and what you already do. AgentGraph serves derived JSON Schema at
   `GET /v1/graphs/schema` with contextual enums injected server-side. Do you consume it? If so
   show the renderer and assess it honestly; if not, why not, and how are node configuration
   forms built instead? How are zod and react-hook-form used — hand-authored TypeScript
   schemas, or derived from what the backend sends? Is there any JSON Schema to zod, or JSON
   Schema to form, layer?
5. Nesting and server-supplied enums. Decision section 3 makes a card's UI a pure recursive
   tree: a scalar field is a leaf, a field whose type is an abstract union is a type-selector
   plus the selected variant's own component inline, three or four levels deep, with enum
   options baked server-side rather than computed in the browser. Can your form layer render
   that today? Show a real example of nested or discriminated-union parameters, or state
   plainly that none exists.
6. Graph rendering. What draws the graph in GraphBuilderPage and GraphMinimap? There is no
   graph library in package.json dependencies — confirm or correct. Could you render an
   auto-laid-out DAG, and with what? DashiBoard emits Graphviz DOT and renders it with
   `@viz-js/viz`.
7. Backend coupling and the services API. Document `src/lib/api.ts`: how
   `VITE_METAGRAPH_API_URL` and `VITE_METAGRAPH_API_KEY` are used, TanStack Query key
   conventions, error handling, and whether there is a vite dev proxy. Then: do you consume
   AgentGraph's `/v1/services` surface — the connection list with provenance, the
   `PUT|DELETE .../connection` overrides, the `/health` probe? That is where the DashiBoard
   server's address lives, and it is how an embedded UI would learn where to point.
8. The config artifact lifecycle in this app. `GraphBuilderPage.tsx:45` and `:1524` carry
   `dashiboardPipelineId`. Document how artifacts are listed, created and referenced today
   (`src/lib/artifacts.ts`, `src/lib/artifactFacts.ts`, `/v1/artifacts`); whether a
   structured_data artifact can be created from the browser; whether uuid-versus-alias
   versioning is surfaced to users; and what the node-side picker needs. Then specify the
   handshake you want from an embedded authoring UI: how does it receive a config to edit, and
   how does it hand a saved one back?
9. Your recommendation. Given a Julia backend serving JSON Schema per card type, specialised to
   the current pipeline's available variables, write the exact shape you want as a TypeScript
   type. Be specific about how nesting and server-supplied enums should be expressed.

Write your brief to (create nothing else, edit nothing else):
/home/dariosarra/Documents/Limen/DashiBoard/.claude/ui-refactor/20-nexus-weaver-brief.md

Then stay available for follow-up questions.
