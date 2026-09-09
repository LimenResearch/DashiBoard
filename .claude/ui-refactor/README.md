# UI refactor — shared coordination folder

Working area for the DashiBoard UI refactor. Four Claude Code sessions write here, one per
repository.

| Session | Repository | Writes |
|---|---|---|
| DashiBoard (lead) | `/home/dariosarra/Documents/Limen/DashiBoard` | `00`, `01`, `02`, `06`, and anything not listed below |
| ExperimentTracking | `/home/dariosarra/Documents/Limen/ExperimentTracking.jl` | `04-experimenttracking-brief.md` only |
| AgentGraph | `/home/dariosarra/Documents/Limen/agentgraph` | `03-agentgraph-brief.md` only |
| nexus-weaver-pro | `/home/dariosarra/Documents/Limen/nexus-weaver-pro` | `05-nexus-weaver-brief.md` only |

## Contents

Files are numbered in reading order.

| File | What it is |
|---|---|
| `00-dashiboard-context.md` | DashiBoard as it stands today. Facts, no decisions. |
| `01-decisions.md` | **The specification.** What has been decided, and what is still open. |
| `02-stack.md` | The four projects and how they connect. |
| `03-agentgraph-brief.md` | AgentGraph reconnaissance. |
| `04-experimenttracking-brief.md` | ExperimentTracking reconnaissance. |
| `05-nexus-weaver-brief.md` | nexus-weaver-pro reconnaissance. |
| `06-design.md` | **The implementation plan.** Ordered by what blocks what. |
| `07-json-schema-and-ui.md` | How a card types itself, and where the projection leaks. Background for A1a, A3, A7. |
| `08-frontend-rebuild.md` | **The frontend rebuild.** What to build on and in what order, for the team leader. Postdates the IR landing and the three reconnaissance answers. |
| `prompt-*.md` | The launch prompt for each session. Unnumbered — inputs, not reading. |

**Reading order for a new session:** `00`, then `01`, then `02`, then your own prompt.

## Branch

All four repositories use a branch named **`ds-DashiUI`**, cut from an up-to-date `main` with
`git checkout --no-track -b ds-DashiUI`. Because **all four repositories use that same branch name**,
never cite it unqualified — say which repository, as the citation rule below already requires for
paths. A nexus-weaver-pro session went looking for `Pipelines.card_ir` in its own `ds-DashiUI` after
reading an unqualified reference to it.

The `--no-track` matters: `main` is unprotected, and a
tracking branch makes git's suggested push land on it.

## Protocol

- **One file per author.** Do not edit a file another session owns. To respond to something
  in another session's brief, write it in your own file or send a message.
- **Cite paths and line numbers** for every factual claim, as `repo:path/to/file.ext:LINE`.
- **Mark inference.** Prefix anything not read directly from source with `INFERRED:`.
- **Do not speculate about another repository.** Ask that session instead.
- **`01-decisions.md` is binding.** If your findings contradict it, say so explicitly and give
  your reason rather than quietly working around it.
- This folder is committed to the DashiBoard repository. Keep it free of secrets.
