import { createEffect, createSignal, For, Show } from "solid-js";

// The keys of the typed entry, by two paths rather than a button on every field: a quiet ⓘ beside
// each box, which the pointer hovers, and one reachable ⓘ in the row of actions, which is also
// what F1 opens from wherever the caret is.

/** Open from anywhere: a box hit F1, or the row's own button was pressed. */
export const [helpOpen, setHelpOpen] = createSignal(false);

const KEYS: [string, string][] = [
  ["c, g or n → Tab", "choose cols, groups or nodes"],
  ["type → Tab", "take the top match; ↑ ↓ choose another"],
  ["Tab, nothing typed", "leave the field"],
  ["a node after a name", "pass through it; repeat for a chain"],
  ["Enter", "add what is in the box"],
  ["Backspace", "undo the last part"],
  ["Esc", "close the list, then clear the box"],
  ["F1", "show these keys"],
];

/**
 * One key per line, its effect under it.
 *
 * Two columns folded the long entries into three or four lines each, which is what made the panel
 * hard to read: the key column is as wide as its longest entry and the rest is what is left.
 */
function Keys(props: { single?: boolean }) {
  return (
    <dl class="flex flex-col gap-1.5">
      <For each={KEYS}>
        {([keys, effect]) => (
          <div>
            <dt class="font-mono whitespace-nowrap text-primary">{keys}</dt>
            <dd class="text-muted-foreground">{effect}</dd>
          </div>
        )}
      </For>
      <div>
        <dt class="font-mono whitespace-nowrap text-primary">← from the empty box</dt>
        <dd class="text-muted-foreground">
          reach the chips; there Delete removes
          {props.single === true ? "" : ", and Alt+← / Alt+→ reorder"}
        </dd>
      </div>
    </dl>
  );
}

/** What the panel would like; with less room above than this it looks below instead. */
const TALL = 320;
const GAP = 8;

type Place = { up: boolean; max: number };

/**
 * Upward by preference, so the panel never covers the suggestions under the box — but the page is
 * as likely to be short, and a panel cut off at the edge of the window cannot be read. So: up when
 * there is room up there, else whichever side has more, and never taller than that side.
 */
function place(anchor: Element | undefined): Place {
  const rect = anchor?.getBoundingClientRect();
  if (rect === undefined) return { up: true, max: TALL };
  const room = { up: rect.top - GAP, down: window.innerHeight - rect.bottom - GAP };
  const up = room.up >= TALL || room.up >= room.down;
  return { up, max: Math.max(120, Math.floor(up ? room.up : room.down)) };
}

const note = (edge: "left" | "right", at: Place) =>
  [
    `absolute ${edge}-0 z-30 w-72 max-w-[80vw] rounded-sm border border-border bg-card p-2 text-control-xs shadow-sm`,
    // The side may still be short on a small window; scrolling beats being cut off.
    "overflow-y-auto",
    at.up ? "bottom-full mb-1" : "top-full mt-1",
  ].join(" ");

/** The pointer's path: a glyph beside the box, hovered, never focused and never clicked. */
export function HelpTip(props: { single?: boolean }) {
  const [shown, setShown] = createSignal(false);
  const [at, setAt] = createSignal<Place>({ up: true, max: TALL });
  let mark: HTMLSpanElement | undefined;
  return (
    <div class="relative shrink-0">
      <span
        data-help-tip
        aria-hidden="true"
        tabindex={-1}
        ref={(el) => { mark = el; }}
        onMouseEnter={() => { setAt(place(mark)); setShown(true); }}
        onMouseLeave={() => setShown(false)}
        class="grid h-6 w-5 cursor-help place-items-center text-control-xs text-muted-foreground"
      >
        ⓘ
      </span>
      <Show when={shown()}>
        <div role="note" tabindex={-1} style={{ "max-height": `${at().max}px` }} class={note("left", at())}>
          <Keys single={props.single} />
        </div>
      </Show>
    </div>
  );
}

/** The keyboard's path: one button for the page, and what F1 opens. */
export function HelpButton() {
  const [at, setAt] = createSignal<Place>({ up: true, max: TALL });
  let trigger: HTMLButtonElement | undefined;
  // Opened by F1 as well as by the button, so where it goes is decided whenever it opens.
  createEffect(helpOpen, (open) => { if (open) setAt(place(trigger)); });
  return (
    <div class="relative shrink-0" onFocusOut={() => setHelpOpen(false)}>
      <button
        type="button"
        data-help
        aria-label="how to type a selection"
        aria-expanded={helpOpen() ? "true" : "false"}
        ref={(el) => { trigger = el; }}
        onClick={() => setHelpOpen(!helpOpen())}
        onKeyDown={(event) => { if (event.key === "Escape") setHelpOpen(false); }}
        class="grid h-control-xs w-6 place-items-center rounded-sm border border-border text-control-xs text-muted-foreground hover:border-primary hover:text-primary"
      >
        ⓘ
      </button>
      <Show when={helpOpen()}>
        <div role="note" tabindex={-1} style={{ "max-height": `${at().max}px` }} class={note("right", at())}>
          <Keys />
        </div>
      </Show>
    </div>
  );
}
