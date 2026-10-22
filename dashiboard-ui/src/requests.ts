import { isRpcError, type RpcError } from "./rpcError";

// The API base address is resolved at RUNTIME, never baked into the bundle.
// One build therefore works served by ExperimentTracking beside the API (same origin, relative
// URLs) and served from a dev server against DashiBoard on another port, with no rebuild.
//
// Resolution order, highest first:
//   1. setApiBase(...)              — set by code; the embed handshake uses this
//   2. ?api=<url> on the page URL   — dev, and a quick manual override
//   3. <meta name="dashi-api">      — injected by whatever serves the page
//   4. globalThis.__DASHI_API__     — set before the bundle loads
//   5. "" — same origin, relative paths

const TRAILING_SLASHES = /\/+$/;
const LEADING_SLASHES = /^\/+/;

const clean = (value: string) => value.replace(TRAILING_SLASHES, "");

let override: string | null = null;

/** Set (or with `null`, clear) the API base at runtime. */
export function setApiBase(url: string | null) {
  override = url === null ? null : clean(url);
}

function fromQuery(): string | null {
  if (typeof window === "undefined") return null;
  const value = new URLSearchParams(window.location.search).get("api");
  return value ? clean(value) : null;
}

function fromMeta(): string | null {
  if (typeof document === "undefined") return null;
  const value = document
    .querySelector('meta[name="dashi-api"]')
    ?.getAttribute("content");
  return value ? clean(value) : null;
}

function fromGlobal(): string | null {
  const value = (globalThis as Record<string, unknown>).__DASHI_API__;
  return typeof value === "string" && value ? clean(value) : null;
}

/** The API base in effect, or `""` meaning same-origin. */
export function apiBase(): string {
  return override ?? fromQuery() ?? fromMeta() ?? fromGlobal() ?? "";
}


export function downloadJSON(obj: any, ref: HTMLAnchorElement) {
  const data = JSON.stringify(obj);
  const blob = new Blob([data], { type: "application/json" });
  const href = window.URL.createObjectURL(blob);
  ref.href = href;
  ref.click();
  ref.href = "";
  window.URL.revokeObjectURL(href);
}

// Every call is JSON-RPC 2.0 to one of three endpoints: `rpc-stream` for a reply that is a file
// or a page of rows rather than an envelope, `rpc-probe` for the run checked without running it.
const STREAMED = new Set(["bundle-pipeline", "fetch-data", "get-processed-data"]);

function endpointOf(page: string): { endpoint: string; method: string } {
  if (page === "probe-pipeline") return { endpoint: "rpc-probe", method: "evaluate-pipeline" };
  return { endpoint: STREAMED.has(page) ? "rpc-stream" : "rpc", method: page };
}

let lastId = 0;

function rpcFetch(page: string, params: unknown): Promise<Response> {
  const { endpoint, method } = endpointOf(page);
  return fetch(getURL(endpoint), {
    method: "POST",
    body: JSON.stringify({ jsonrpc: "2.0", id: ++lastId, method, params }),
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * A call whose answer is a file — a zip — or, when the server refused, its error.
 * `null` when the server could not be reached at all, as `postRequest` answers.
 */
export async function postBlob(
  page: string, body: unknown,
): Promise<{ blob: Blob; filename: string } | RpcError | null> {
  try {
    const response = await rpcFetch(page, body);
    const type = response.headers.get("Content-Type") ?? "";
    if (!response.ok) {
      // Neither the file nor the server's own JSON — a proxy's 404 page, a bare 500 — is no
      // answer, and must not be saved as if it were the file.
      const reply = type.includes("application/json") ? await response.json() : null;
      return isRpcError(reply) ? { error: reply.error } : null;
    }
    if (!type.includes("application/zip")) return null;
    const disposition = response.headers.get("Content-Disposition") ?? "";
    const filename = /filename="?([^";]+)"?/.exec(disposition)?.[1] ?? `${page}.zip`;
    return { blob: await response.blob(), filename };
  } catch {
    console.log("Request to " + page + " failed");
    return null;
  }
}

/** Hand the browser a file to save, under `filename`. */
export function saveBlob(blob: Blob, filename: string) {
  const href = window.URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = href;
  anchor.download = filename;
  anchor.click();
  window.URL.revokeObjectURL(href);
}

export function getURL(page: string) {
  const base = apiBase();
  const path = page.replace(LEADING_SLASHES, "");
  return base ? `${base}/${path}` : `/${path}`;
}

/**
 * Call `page` and resolve to its result, to `{error}` when the server refused, or to `def` when
 * it could not be reached or did not answer in JSON. A streamed reply is the result itself when
 * it succeeded, so its status says which it is.
 */
export function postRequest(page: string, body: any, def: any) {
  return rpcFetch(page, body)
    .then(async (response) => {
      const reply = await response.json();
      if (STREAMED.has(page) && response.ok) return reply;
      return isRpcError(reply) ? { error: reply.error } : reply.result;
    })
    .catch((_) => {
      console.log("Request to " + page + " failed");
      return def;
    });
}
