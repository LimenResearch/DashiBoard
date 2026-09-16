import { postRequest } from "./requests";
import { emptyProbe, type CardsStore, type ProbeStore } from "./stores";

// One place to ask `POST /probe-pipeline`. The card Confirm, the continuous probe and — since the
// empty-group check moved to the server — the group Confirm all ask the same question.

/** Coerce a probe reply into something the store can hold, whatever the server sent. */
export const usableProbe = (result: unknown): ProbeStore => {
  const reported = result as ProbeStore | null;
  const ok = reported !== null && typeof reported === "object" &&
    Array.isArray(reported.nodes) && Array.isArray(reported.errors);
  return ok ? { ...reported, issues: Array.isArray(reported.issues) ? reported.issues : [] } : emptyProbe();
};

/** Ask once and get the shape back. */
export async function askProbe(document: CardsStore): Promise<ProbeStore> {
  return usableProbe(await postRequest("probe-pipeline", document, null));
}
