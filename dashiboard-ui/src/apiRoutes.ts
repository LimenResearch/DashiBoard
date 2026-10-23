// Every route the form reaches — the three JSON-RPC endpoints and the table download link — in one
// list: the dev server's proxy is built from it, and a test checks the sources against it. A route
// left off falls through to the dev server itself, whose 404 page the form can only read as "the
// server is down".

/** The route a document kind is read and written through: `read-pipeline`, `write-filters`. */
export const DOCUMENT_ROUTES = { cards: "pipeline", filters: "filters" } as const;

export const API_ROUTES = [
  "/rpc",
  "/rpc-probe",
  "/rpc-stream",
  "/get-processed-data",
] as const;
