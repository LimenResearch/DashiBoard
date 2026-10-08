import { createEffect, createSignal, For, onCleanup, Show } from "solid-js";

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
  ["| or select… after a node", "keep only some of its products"],
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

// The side may still be short on a small window; scrolling beats being cut off.
const SKIN =
  "w-72 max-w-[80vw] overflow-y-auto rounded-sm border border-border bg-card p-2 text-control-xs shadow-sm";

// `z-40` is the top of the stack here: the sticky action row is 10, menus and panels 20, the
// selector's suggestion list 30. This explains the control the reader is using, so it is the one
// thing that must never be drawn under.
const note = (edge: "left" | "right", at: Place) =>
  [`absolute ${edge}-0 z-40 ${SKIN}`, at.up ? "bottom-full mb-1" : "top-full mt-1"].join(" ");

/** Where the page-level panel goes, in viewport coordinates — see `HelpButton` for why. */
function anchor(trigger: Element | undefined) {
  const at = place(trigger);
  const rect = trigger?.getBoundingClientRect();
  if (rect === undefined) return { ...at, right: GAP, y: GAP };
  return {
    ...at,
    right: Math.max(GAP, window.innerWidth - rect.right),
    y: at.up ? window.innerHeight - rect.top + GAP : rect.bottom + GAP,
  };
}

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

// Where the open panel sits, and the panel itself, so that `HelpPanel` can be rendered somewhere
// else in the tree from the button that opens it. That separation is the whole point: the button
// belongs in the sticky action row, and `position: sticky` with a `z-index` makes that row a
// stacking context — everything inside is capped at the row's layer, so no z-index could lift the
// panel above the selector's suggestion list in a context of its own. Solid 2 has no `Portal`, so
// the panel is rendered outside the row instead and placed in viewport coordinates.
const [helpAt, setHelpAt] = createSignal({ up: true, max: TALL, right: GAP, y: GAP });
let panelEl: HTMLDivElement | undefined;

/**
 * The keys themselves, which `HelpButton` opens but does not contain.
 *
 * Render it outside any stacking context that would trap it — in practice, as a sibling of the
 * action row rather than inside it.
 */
export function HelpPanel() {
  return (
    <Show when={helpOpen()}>
      <div
        ref={(el) => { panelEl = el; }}
        role="note"
        tabindex={-1}
        style={{
          position: "fixed",
          right: `${helpAt().right}px`,
          [helpAt().up ? "bottom" : "top"]: `${helpAt().y}px`,
          "max-height": `${helpAt().max}px`,
        }}
        class={`z-40 ${SKIN}`}
      >
        <Keys />
      </div>
    </Show>
  );
}

/** The keyboard's path: one button for the page, and what F1 opens. */
export function HelpButton() {
  let trigger: HTMLButtonElement | undefined;
  let wrapper: HTMLDivElement | undefined;
  // Opened by F1 as well as by the button, so where it goes is decided whenever it opens.
  createEffect(helpOpen, (open) => { if (open) setHelpAt(anchor(trigger)); });

  // F1 leaves the caret where it was, so focus never enters this panel and focus leaving it
  // cannot be what puts it away. Carrying on anywhere else does. One listener for this
  // component's life: registering it per opening leaves one behind on unmount, and the next
  // panel — the state is shared — is closed by the one before it.
  const elsewhere = (event: Event) => {
    const target = event.target as Node;
    // The panel is no longer inside the wrapper, so it has to be asked separately.
    if (helpOpen() && !wrapper?.contains(target) && !panelEl?.contains(target)) setHelpOpen(false);
  };
  document.addEventListener("mousedown", elsewhere, true);
  onCleanup(() => document.removeEventListener("mousedown", elsewhere, true));
  return (
    <div ref={(el) => { wrapper = el; }} class="relative shrink-0" onFocusOut={() => setHelpOpen(false)}>
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
    </div>
  );
}
