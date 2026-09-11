import { createSignal } from "solid-js";

// Light/dark mode.
//
// Three rules come from C5 and from the host's own implementation, and none of them are ours to
// reinvent:
//
//   * **The mode arrives in the frame URL as `?theme=dark`, read once at load and never again.**
//     That is what lets an embedded frame know the mode before first paint, so a light panel never
//     flashes inside a dark app. A host must never re-navigate the frame to change it — that
//     remounts the app and destroys its state, which is a worse bug than the flash it avoids.
//     Later changes arrive by postMessage instead (not built yet).
//   * **No third state.** The host matches the OS silently at launch and shows only light/dark,
//     its owner having judged a monitor icon to be a state label rather than an affordance.
//   * **Standalone has to work on its own** (§9 layer 1), so the OS preference is the fallback and
//     the toggle is a real control here, not a stand-in for a host that is missing.

export type ThemeMode = "light" | "dark";

/** The mode explicitly asked for, or `null` when the URL says nothing. */
export function modeFromSearch(search: string): ThemeMode | null {
  const asked = new URLSearchParams(search).get("theme");
  return asked === "dark" || asked === "light" ? asked : null;
}

/** What to open with: an explicit request beats the OS, and the OS beats a guess. */
export function initialMode(search: string, prefersDark: boolean): ThemeMode {
  return modeFromSearch(search) ?? (prefersDark ? "dark" : "light");
}

export const [themeMode, setThemeMode] = createSignal<ThemeMode>("light");

export const toggleTheme = () => setThemeMode(themeMode() === "dark" ? "light" : "dark");

/**
 * Put the mode on the document.
 *
 * A class rather than a data attribute, because that is what the host's `.dark` block uses and
 * what a shared stylesheet would expect. Takes the root element instead of reaching for
 * `document`, so it is callable in a test and unreachable during SSR.
 */
export function applyTheme(mode: ThemeMode, root: Element) {
  root.classList.toggle("dark", mode === "dark");
}
