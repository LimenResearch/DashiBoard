import type { PipelineNode } from "./stores";

// What the UI can answer about a definition on its own, without asking the server.
//
// The line between this module and the probe is *scope*, not severity: this module answers
// questions about one definition in isolation, the probe answers everything that depends on the
// graph. A field nobody filled in is ours — it is visible in the card in front of you — while an
// unproduced reference or a cycle is the server's, since neither can be seen without the other
// cards. A duplicate id is ours only because `setNodeId` refuses one at the name field.
//
// Whatever the server can answer, the server answers. A card's schema — a required field absent,
// a list below its minimum, a value outside an enum — is asked of it per card through
// `POST /validate-card`, and an empty group is reported by the probe. So `checkNode` and
// `checkNames` are all that is left here.
//
// What this module does name is read from the IR, never decided here: the IR is the server's own
// description, fetched from `get-card-ir`, and `widgetFor` is the same descriptor the renderer
// dispatches on — so a field named here is always a field drawn on screen, and it cannot drift
// from what the schema admits without the form drifting too. Where a rule looks like a judgement
// call — may a required list be empty? — it is read from the node, because the same question has
// different answers on different cards (see `checkFields`).

export type Incompleteness = {
  /** What the author would do about it, phrased as the thing to do rather than as a complaint. */
  message: string;
  /**
   * Where, as a JSON Pointer into the document — the server's own scheme, so a finding from here
   * and one from the server render through one code path and read the same way.
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

/**
 * Cards that share a name with an earlier card — the later ones, each with its finding.
 *
 * The server refuses such a document with no pointer, so it cannot say which card; the UI can.
 * `setNodeId` enforces this at the name field, so two cards with one name can only arrive in a
 * loaded document — which is marked rather than refused, the form being there to fix it. A
 * missing id counts as "", the server's own default, so two unnamed cards collide the same way.
 * The first holder keeps its name unmarked: it is the later card that has to change.
 */
export function checkNames(
  nodes: readonly PipelineNode[],
): { index: number; finding: Incompleteness }[] {
  const seen = new Set<string>();
  const out: { index: number; finding: Incompleteness }[] = [];
  nodes.forEach((node, index) => {
    const id = node.id ?? "";
    if (seen.has(id)) {
      out.push({
        index,
        finding: {
          message: id === ""
            ? "There is already a card without a name."
            : `There is already a card called "${id}".`,
        },
      });
    }
    seen.add(id);
  });
  return out;
}
