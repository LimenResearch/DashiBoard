import { resetSession } from "../session";

// Always in the nav, not only behind the gate — a session that was never gated (started fresh,
// or the gate already answered) still has data worth discarding deliberately (task brief). Same
// button classes as `ThemeToggle`, so the two read as one control group in the nav.

export function StartOver() {
  return (
    <button
      type="button"
      onClick={() => { if (window.confirm("Discard the loaded table, filters and cards?")) resetSession(); }}
      class="inline-flex h-control-xs items-center rounded-sm px-2 text-control-xs text-primary-foreground/80 transition-colors hover:bg-primary-foreground/10 hover:text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
      Start over
    </button>
  );
}
