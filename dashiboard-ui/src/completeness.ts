import type { PipelineNode, Selector } from "./stores";

// Definitions that are **legal but unfinished**.
//
// This is a category with one membership rule, and the rule is the whole reason it can exist
// without becoming a second validator:
//
//   A check belongs here only if DashiBoard *accepts* the document.
//
// If the server would reject it, the probe already reports it with a JSON Pointer (A7) and an
// enumeration of what was allowed — duplicating that here would be a second source of truth for
// the schema, which is the mistake A10 exists to delete and the one C2's second constraint was
// withdrawn for. Anything the server can answer, the server answers.
//
// What is left over is small, and that is the point rather than a gap: almost everything a person
// gets wrong is already caught, so this list holds only the things that are *legal, constructible
// and pointless*. Each one is a sentence the schema cannot say.
//
// Two are deliberately absent:
//
//   * A required field left empty. The schema says `required`, so construction fails and the probe
//     reports it against the exact field. Nothing to add.
//   * A group nothing refers to. Legal, and usually just means the cards that use it have not been
//     written yet — a rule that fires through most of an authoring session teaches people to
//     ignore it.

export type Incompleteness = {
  /** What the author would do about it, phrased as the thing to do rather than as a complaint. */
  message: string;
};

/**
 * A group with no selectors resolves to no columns.
 *
 * Measured rather than assumed: `weather = []` constructs fine, so the server will never mention
 * it. It is also never what anyone meant — a group exists to name a set of columns once.
 */
export function checkGroup(items: readonly Selector[]): Incompleteness[] {
  if (items.length === 0) {
    return [{ message: "Add at least one column, group or node — an empty group selects nothing." }];
  }
  return [];
}

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
