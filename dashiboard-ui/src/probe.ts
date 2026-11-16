import { postRequest } from "./requests";
import { failureOf, isRpcError } from "./rpcError";
import type { CardsStore, ProbeIssue, ProbeNode, ProbeStore } from "./stores";

// One place to ask `POST /probe-pipeline`. The card Confirm, the continuous probe and — since the
// empty-group check moved to the server — the group Confirm all ask the same question.

/**
 * Coerce a probe reply into something the store can hold, whatever the server sent.
 *
 * Normalised field by field, never rejected whole: a refusal's report carries no `nodes`, only
 * `{kind, errors, issues}` plus `cols` on the schema path, and its issues must still reach the
 * store. Absent fields become empty lists.
 *
 * The server sends no verdict: it accepts a document by answering and refuses it with an error.
 * `valid` is that envelope, read by the caller — a result is valid, a refusal is not.
 */
const usableReferable = (x: unknown): ProbeStore["referable"] => {
  const r = x as { nodes?: unknown; groups?: unknown } | null | undefined;
  const shaped = typeof r === "object" && r !== null && Array.isArray(r.nodes) &&
    typeof r.groups === "object" && r.groups !== null;
  return shaped ? (r as ProbeStore["referable"]) : null;
};

export const usableProbe = (result: unknown, valid = true): ProbeStore => {
  const r = (result ?? {}) as Partial<ProbeStore>;
  const list = <T,>(x: unknown): T[] => (Array.isArray(x) ? (x as T[]) : []);
  return {
    valid,
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
 * parse its reply as JSON — including the 404 HTML a missing dev-server proxy route answers with.
 * `usableProbe(null)` reads as `{valid: true, issues: []}`, the shape of a clean bill of health, so
 * it would make a probe that never reached the server look like one that found nothing wrong.
 * Callers must treat `null` as "could not check", never as "no issues" — see
 * `GroupsEditor.tsx`'s Confirm handler and `processing.tsx`'s `confirmNode`.
 */
export async function askProbe(document: CardsStore): Promise<ProbeStore | null> {
  const result = await postRequest("probe-pipeline", document, null);
  // A document that does not build is refused, and the refusal carries the issues to mark.
  if (isRpcError(result)) return usableProbe(failureOf(result), false);
  return result !== null && typeof result === "object" ? usableProbe(result) : null;
}
