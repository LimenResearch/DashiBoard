import { createSignal, For, Show } from "solid-js";

// The keys of the typed entry, behind a button TAB can reach: a hover tip alone would be out of
// reach for exactly the people the text box is for.

const KEYS: [string, string][] = [
  ["c, g or n, then Tab", "choose cols, groups or nodes (the list is always showing)"],
  ["type, then Tab", "take the top match (↑ ↓ to choose another); Tab with nothing typed leaves"],
  ["a node after a name (@ optional)", "pass through it; repeat for a chain — only nodes that read the value are offered"],
  ["Enter", "add it"],
  ["Backspace", "undo the last part"],
  ["Esc", "close the list, then clear"],
];

export function SelectorHelp(props: { single?: boolean }) {
  const [open, setOpen] = createSignal(false);
  return (
    <div class="relative shrink-0">
      <button
        type="button"
        data-help
        aria-label="how to type a selection"
        aria-expanded={open() ? "true" : "false"}
        onClick={() => setOpen(!open())}
        onKeyDown={(event) => { if (event.key === "Escape") setOpen(false); }}
        class="grid h-6 w-5 place-items-center rounded-sm border border-border text-control-xs text-muted-foreground hover:border-primary hover:text-primary"
      >
        ?
      </button>
      <Show when={open()}>
        <div
          role="note"
          class="absolute top-7 left-0 z-20 w-80 rounded-sm border border-border bg-card p-2 text-control-xs shadow-sm"
        >
          <dl class="grid grid-cols-[auto_1fr] gap-x-2 gap-y-1">
            <For each={KEYS}>
              {([keys, effect]) => (
                <>
                  <dt class="font-mono whitespace-nowrap text-primary">{keys}</dt>
                  <dd class="text-muted-foreground">{effect}</dd>
                </>
              )}
            </For>
            <dt class="font-mono whitespace-nowrap text-primary">← from the empty box</dt>
            <dd class="text-muted-foreground">
              reach the chips; there Delete removes
              {props.single === true ? "" : ", and Alt+← / Alt+→ reorder"}
            </dd>
          </dl>
        </div>
      </Show>
    </div>
  );
}
