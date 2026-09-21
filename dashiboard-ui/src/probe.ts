import { postRequest } from "./requests";
import type { CardsStore, ProbeIssue, ProbeNode, ProbeStore } from "./stores";

// One place to ask `POST /probe-pipeline`. The card Confirm, the continuous probe and — since the
// empty-group check moved to the server — the group Confirm all ask the same question.

/**
 * Coerce a probe reply into something the store can hold, whatever the server sent.
 *
 * Normalised field by field, never rejected whole. A *failed* probe carries no `nodes`: the
 * server's `failure_report` is `{valid, kind, errors, issues}`, plus `cols` on the probe's
 * schema path. The old shape test required `nodes` before it would keep anything, so every real
 * failure reply was replaced by `emptyProbe()` — `valid: true`, no issues — which is what let an
 * empty group be confirmed with a green dot (final review, 2026-09-16). Absent fields become
 * empty lists and an absent `valid` reads as true, so a reply that says nothing says nothing
 * wrong.
 */
const usableReferable = (x: unknown): ProbeStore["referable"] => {
  const r = x as { nodes?: unknown; groups?: unknown } | null | undefined;
  const shaped = typeof r === "object" && r !== null && Array.isArray(r.nodes) &&
    typeof r.groups === "object" && r.groups !== null;
  return shaped ? (r as ProbeStore["referable"]) : null;
};

export const usableProbe = (result: unknown): ProbeStore => {
  const r = (result ?? {}) as Partial<ProbeStore>;
  const list = <T,>(x: unknown): T[] => (Array.isArray(x) ? (x as T[]) : []);
  return {
    valid: r.valid !== false,
    cols: list<string>(r.cols),
    nodes: list<ProbeNode>(r.nodes),
    errors: list<string>(r.errors),
    issues: list<ProbeIssue>(r.issues),
    referable: usableReferable(r.referable),
  };
};

/**
 * Ask once and get the shape back — or `null` when there is no shape to normalise.
 *
 * `postRequest` resolves to its `def` (`null`, passed below) on any failure to reach the server or
 * parse its reply as JSON — including the 404 HTML a missing dev-server proxy route answers with
 * (item 1). `usableProbe(null)` reads as `{valid: true, issues: []}`, the shape of a clean bill of
 * health, which is how a probe that never reached the server used to look identical to one that
 * found nothing wrong. Callers must treat `null` as "could not check", never as "no issues" — see
 * `GroupsEditor.tsx`'s Confirm handler and `processing.tsx`'s `confirmNode`.
 */
export async function askProbe(document: CardsStore): Promise<ProbeStore | null> {
  const result = await postRequest("probe-pipeline", document, null);
  return result !== null && typeof result === "object" ? usableProbe(result) : null;
}
