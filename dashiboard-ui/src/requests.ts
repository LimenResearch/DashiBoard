// The API base address is resolved at RUNTIME, never baked into the bundle (decisions 11 / C6).
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


export function loadJSON(input: HTMLInputElement, def: any) {
  const files = input.files ?? new FileList();
  return files[0]
    .text()
    .then(JSON.parse)
    .catch((_) => {
      console.log("Could not load file.");
      return def;
    });
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
