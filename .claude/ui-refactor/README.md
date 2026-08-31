# UI refactor — shared coordination folder

Working area for the DashiBoard UI refactor. Four Claude Code sessions write here, one per
repository.

| Session | Repository | Writes |
|---|---|---|
| DashiBoard (lead) | `/home/dariosarra/Documents/Limen/DashiBoard` | `00`, `01`, `02`, `30`, and anything not listed below |
| ExperimentTracking | `/home/dariosarra/Documents/Limen/ExperimentTracking.jl` | `15-experimenttracking-brief.md` only |
| AgentGraph | `/home/dariosarra/Documents/Limen/agentgraph` | `10-agentgraph-brief.md` only |
| nexus-weaver-pro | `/home/dariosarra/Documents/Limen/nexus-weaver-pro` | `20-nexus-weaver-brief.md` only |

## Contents

| File | What it is |
|---|---|
| `00-dashiboard-context.md` | DashiBoard as it stands today. Facts, no decisions. |
| `01-decisions.md` | **The specification.** What has been decided, and what is still open. |
| `02-stack.md` | The four projects and how they connect. |
| `prompt-*.md` | The launch prompt for each session. |
| `10`/`15`/`20-*-brief.md` | Reconnaissance, written by each session. |
| `30-design.md` | The resulting design, written last by the lead session. |

**Reading order for a new session:** `00`, then `01`, then `02`, then your own prompt.

## Branch

All four repositories use a branch named **`ds-DashiUI`**, cut from an up-to-date `main` with
`git checkout --no-track -b ds-DashiUI`. The `--no-track` matters: `main` is unprotected, and a
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
