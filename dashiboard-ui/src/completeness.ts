import { widgetFor, type Defs, type IRNode, type Widget } from "./ir";
import type { PipelineNode, Selector } from "./stores";

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

export type Incompleteness = {
  /** What the author would do about it, phrased as the thing to do rather than as a complaint. */
  message: string;
  /**
   * Where, as a JSON Pointer into the document, in A7's scheme — so a finding from here and one
   * from the server render through one code path and read the same way.
   */
  pointer?: string;
};

/**
 * A group with no selectors resolves to no columns.
 *
 * Measured rather than assumed: `weather = []` constructs fine, so the server will never mention
 * it. It is also never what anyone meant — a group exists to name a set of columns once. This one
 * is still about a document the server *accepts*, which is why it reads as a warning rather than
 * as an error.
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

// --- unanswered fields ------------------------------------------------------------------------

/** `~` before `/`, or the escape introduced by the first pass would be escaped by the second. */
const escapeToken = (token: string) => token.replace(/~/g, "~0").replace(/\//g, "~1");

const isRecord = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const absent = (value: unknown) => value === undefined || value === null;

const oneOf = (options: readonly (string | number)[]) =>
  `choose one of: ${options.map(String).join(", ")}`;

/**
 * What this node still needs, or `null` if the value answers it.
 *
 * One case per widget kind, so the question asked of a field is the one its own control poses: a
 * variant wants a branch named, a repeater wants items, a number wants a number.
 */
function unanswered(w: Widget, value: unknown): string | null {
  switch (w.kind) {
    // Nothing honest to say. `ArrayIR{Any}()` serialises its items as `{}` — glm's formula — and
    // a check that guesses at a field it cannot describe is a check that argues with the author.
    case "unknown":
      return null;

    case "object":
      return isRecord(value) ? null : "needs a value";

    case "variant": {
      const chosen = isRecord(value) ? value.type : undefined;
      return typeof chosen === "string" && w.options.includes(chosen) ? null : oneOf(w.options);
    }

    case "select":
      return absent(value) ? oneOf(w.options) : null;

    case "number":
      return typeof value === "number" ? null : "needs a number";

    case "toggle":
      return typeof value === "boolean" ? null : "needs true or false";

    case "text":
      if (typeof value !== "string") return "needs a value";
      // Blank counts as unanswered only where the IR says a value must have length — which it
      // does for `suffix`, and does not for a free-text field that may legitimately be empty.
      return value === "" && (w.minLength ?? 0) > 0 ? "needs a value" : null;

    case "multiselect":
    case "repeater": {
      const min = w.minItems ?? 0;
      if (Array.isArray(value) && value.length >= min) return null;
      // A minimum is the more useful thing to say, whether the list is empty or absent: "select
      // at least one" tells the author what to do, where "needs a value" only says something is
      // wrong. Without a minimum there is nothing to quantify, so an absent list falls back.
      if (min >= 1) return min === 1 ? "select at least one" : `select at least ${min}`;
      return "needs a value";
    }

    // One selector item. `kinds` comes from the `oneOf` the IR carries, so this asks the question
    // the schema asks. Only *none chosen* is reported: whether two kinds were given at once is
    // the server's to judge, and C2 makes it unrepresentable here anyway.
    case "selector": {
      if (!isRecord(value)) return "needs a value";
      return w.kinds.some((kind) => !absent(value[kind])) ? null : oneOf(w.kinds);
    }
  }
}

/**
 * Every required field below `node` that nobody has answered, each addressed by pointer.
 *
 * `pointer` is where `node` sits in the document — `/nodes/0/card` for a card — and grows by one
 * segment per level, so a finding addresses the control that would fix it. Numeric segments are
 * document positions, which `fieldPath` shifts for display.
 *
 * Two structural decisions worth stating, because both are places a reasonable implementation
 * would differ:
 *
 * A **variant's branch shares its parent's pointer and value.** `{type: "dbscan", radius: …}` is
 * one flat object, which is how the renderer draws it too, so `radius` is `…/method/radius` and
 * not `…/method/dbscan/radius`.
 *
 * **Requiredness comes from the parent's property entry**, never from the node, because that is
 * where the IR puts it. So the same `$defs/variables` node is unfinished when empty on a cluster
 * card and finished when empty on a rescale card — `nonempty_variables` sets `minItems`, plain
 * `variables` does not. A rule of this module's own invention would have had to pick one.
 */
export function checkFields(
  node: IRNode,
  defs: Defs,
  value: unknown,
  pointer: string,
  required = true,
): Incompleteness[] {
  const w = widgetFor(node, defs);
  const gap = unanswered(w, value);
  // Answered or not, an optional field nobody filled in is finished — and there is nothing below
  // an absent object worth descending into.
  if (gap !== null) return required ? [{ message: gap, pointer }] : [];

  switch (w.kind) {
    case "object":
      return w.properties.flatMap((entry) =>
        checkFields(
          entry.value,
          defs,
          (value as Record<string, unknown>)[entry.key],
          `${pointer}/${escapeToken(entry.key)}`,
          entry.required,
        ),
      );

    case "variant": {
      const branch = w.objects[(value as Record<string, unknown>).type as string];
      return branch === undefined ? [] : checkFields(branch, defs, value, pointer, true);
    }

    // An item that exists has to be answered, however the list got its length. Reachable through
    // an uploaded document rather than through the picker, which never writes an empty item.
    case "repeater":
      return (value as unknown[]).flatMap((item, index) =>
        checkFields(w.items, defs, item, `${pointer}/${index}`, true),
      );

    default:
      return [];
  }
}
