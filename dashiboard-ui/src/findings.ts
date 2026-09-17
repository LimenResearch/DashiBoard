import type { Incompleteness } from "./completeness";
import type { ProbeIssue } from "./stores";

// Server issues as findings, one per control. Shared by Confirm (cards and groups) and by a failed
// run's verdicts, so an issue is placed the same way whoever asked. Type-only imports: the store
// calls this at runtime, and a runtime import back into the store would be a cycle.

/**
 * Schema issues as findings, one per control rather than one per issue.
 *
 * A `required` failure names every absent field at once and carries a `related` pointer per
 * name (A7), so the server already knows which control each belongs to — the work here is
 * placing them, not finding them.
 */
export const issueFindings = (issues: readonly ProbeIssue[]): Incompleteness[] =>
  issues.flatMap((issue) => {
    if (issue.severity === "warning") {
      return [{ message: issue.message, pointer: issue.pointer, severity: "warning" as const }];
    }
    // The server's graph checks (`empty`, `unproduced` — handlers.jl) write a sentence about the
    // document, not a schema failure with fields to point at: their `message` is the finding.
    if (issue.reason === "empty" || issue.reason === "unproduced") {
      return [{ message: issue.message, pointer: issue.pointer }];
    }
    if (issue.missing.length > 0) {
      return issue.missing.map((name, at) => ({
        message: "needs a value",
        pointer: issue.related[at] ?? `${issue.pointer}/${name}`,
      }));
    }
    if (issue.reason === "enum" && issue.allowed) {
      return [{
        message: `must be one of: ${issue.allowed.map(String).join(", ")}`,
        pointer: issue.pointer,
      }];
    }
    return [{ message: `not accepted (${issue.reason})`, pointer: issue.pointer }];
  });
