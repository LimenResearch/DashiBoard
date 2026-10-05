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

/**
 * A POST whose answer is a file — a zip — or, when the server refused, its JSON envelope.
 * `null` when the server could not be reached at all, as `postRequest` answers.
 */
export async function postBlob(
  page: string, body: unknown,
): Promise<{ blob: Blob; filename: string } | { json: unknown } | null> {
  try {
    const response = await fetch(getURL(page), {
      method: "POST", body: JSON.stringify(body), headers: { "Content-Type": "application/json" },
    });
    const type = response.headers.get("Content-Type") ?? "";
    if (type.includes("application/json")) return { json: await response.json() };
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

export function postRequest(page: string, body: any, def:any) {
  const myHeaders = new Headers();
  myHeaders.append("Content-Type", "application/json");

  const response = fetch(getURL(page), {
    method: "POST",
    body: JSON.stringify(body),
    headers: myHeaders,
  });

  return response
    .then((x) => x.json())
    .catch((_) => {
      console.log("Request to " + page + " failed");
      return def;
    });
}
