import type { PipelineNode } from "./stores";

// What the UI can answer about a definition on its own, without asking the server.
//
// The line between this module and the probe is *scope*, not severity:
//
//   this module answers questions about one definition in isolation;
//   the probe answers everything that depends on the graph.
//
// So a field nobody filled in is ours — it is visible in the card in front of you — while an
// unproduced reference, a duplicate id or a cycle is the server's, because none of them can be
// seen without the other cards. Whatever the server can answer, the server answers: duplicating
// that here would be the second source of truth A10 exists to delete, and C2's second constraint
// was withdrawn over.
//
// An earlier version of this module drew the line at *legality* instead — it held only checks the
// server would accept — and so deliberately excluded required fields, on the reasoning that the
// probe already reports them against the exact field. Two measurements retired that:
//
//   * The probe is a **first-failure** reporter. `validate_pipeline_schema` throws on the first
//     card that fails, and the handler wraps that one exception, so a document with two broken
//     cards comes back with exactly one issue naming the first. Measured: two empty cards yield
//     `[{pointer: "/nodes/0/card", missing: ["method", "inputs"]}]` and nothing about node 1. The
//     failure branch also carries no `nodes`, so the graph analysis is unavailable on exactly the
//     documents that most need it.
//   * The IR is not a second description. It is the server's own, fetched at runtime from
//     `get-card-ir`, and `widgetFor` is the same descriptor the renderer dispatches on — so a
//     field this module names is always a field drawn on screen, and it cannot drift from what
//     the schema admits without the form drifting too. That is §13's whole point: one traversal,
//     two artefacts.
//
// Everything here is therefore derived from the IR rather than decided in this file. Where a rule
// looks like a judgement call — may a required list be empty? — it is read from the node, because
// the same question has different answers on different cards (see `checkFields`).
//
// **The line, after the consolidation of 2026-09-14.** This file holds only checks with no server
// counterpart. Everything a card's schema can answer — a required field absent, a list below its
// minimum, a value outside an enum — is asked of Pipelines directly, per card, through
// `POST /validate-card` over `Pipelines.card_issues`. There was a walk here that re-implemented
// `required` and `minItems` in TypeScript; measured against `validate_pipeline_schema` it found
// exactly the same set, nested cases included, and it is gone.
//
// `checkNode` is what is left. `checkGroup` went on 2026-09-16 when the probe learned to report
// an empty group itself (`empty_group_issues`).

export type Incompleteness = {
  /** What the author would do about it, phrased as the thing to do rather than as a complaint. */
  message: string;
  /**
   * Where, as a JSON Pointer into the document, in A7's scheme — so a finding from here and one
   * from the server render through one code path and read the same way.
   */
  pointer?: string;
  /** A probe finding carries this through; a UI-only check has none and reads as an error. */
  severity?: "error" | "warning";
};

/**
 * A node with no id cannot be referred to.
 *
 * One unnamed node constructs (measured); two collide, because `Pipelines.get_id` defaults a
 * missing id to `""` and the dependency graph rejects duplicates — so the *second* one is the
 * server's to report and the first one is ours. Unnamed, nothing can route through it: no
 * `nodes:` selector and no `through:` chain can name it.
 */
export function checkNode(node: PipelineNode): Incompleteness[] {
  if (!node.id || node.id.trim() === "") {
    return [{ message: "Give this card a name — nothing can refer to it until it has one." }];
  }
  return [];
}
