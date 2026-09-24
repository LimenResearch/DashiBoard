import { themeMode, toggleTheme } from "../theme";

// Two states, no third.
//
// The host settled this and we follow it: it matches the OS silently at launch and never shows a
// "system" state, its owner having judged a monitor icon to be a state label rather than an
// affordance. So the control shows where a click will take you, not where you currently are.

export function ThemeToggle() {
  const next = () => (themeMode() === "dark" ? "light" : "dark");

  return (
    <button
      type="button"
      onClick={() => toggleTheme()}
      aria-label={`switch to ${next()} mode`}
      title={`switch to ${next()} mode`}
      class="inline-flex h-control-xs items-center rounded-sm px-2 text-control-xs text-primary-foreground/80 transition-colors hover:bg-primary-foreground/10 hover:text-primary-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
      {themeMode() === "dark" ? "☀" : "☾"}
    </button>
  );
}
