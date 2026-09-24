import { createMemo, createSignal, For, Show } from "solid-js";

import { Button } from "./Button";
import { SelectorField } from "./SelectorField";
import { presetFields } from "../presets";
import { PRESETS_STORE } from "../stores";
import type { SelectorItem } from "../selector";
import type { Defs, IRNode } from "../ir";

// Starting values for the fields cards share, behind a button beside the ones that make a card.
//
// A panel rather than a permanent item: it is consulted when a card is about to be made and is
// nothing to read the rest of the time. The pickers are the ones a card draws, so a preset is set
// exactly the way the field itself is.

export function Presets(props: { cards: { [type: string]: IRNode }; defs: Defs }) {
  const [presets, setPresets] = PRESETS_STORE;
  const [open, setOpen] = createSignal(false);
  // Below the button when the view has room, above it otherwise: the row it sits in is at the
  // foot of a page that may be short or long.
  const [above, setAbove] = createSignal(false);
  let trigger: HTMLButtonElement | undefined;
  let panel: HTMLDivElement | undefined;

  const fields = createMemo(() => presetFields(props.cards, props.defs));
  const count = () => fields().filter((field) => presets[field.key] !== undefined).length;

  /** A field with nothing in it is no preset at all, so it leaves rather than holding an empty. */
  const keep = (key: string, value: SelectorItem | SelectorItem[] | undefined) =>
    setPresets((draft) => {
      const empty = value === undefined || (Array.isArray(value) && value.length === 0);
      if (empty) delete draft[key];
      else draft[key] = value;
    });

  /** Where the tab round goes inside the panel: a hidden fold (`[hidden]`) is not a stop. */
  const stops = () =>
    [...(panel?.querySelectorAll<HTMLElement>("button, input, [tabindex]") ?? [])]
      .filter((el) => el.tabIndex !== -1 && el.closest("[hidden]") === null);

  const close = () => {
    setOpen(false);
    trigger?.focus();
  };

  return (
    <div class="relative">
      <Button
        menu={{ open: open(), ref: (el) => { trigger = el; } }}
        onClick={() => {
          const below = window.innerHeight - (trigger?.getBoundingClientRect().bottom ?? 0);
          setAbove(below < 360);
          setOpen(!open());
        }}
      >
        <span data-presets>Presets{count() > 0 ? ` ${count()}` : ""}</span>
      </Button>

      <Show when={open()}>
        <div
          role="dialog"
          aria-label="presets for new cards"
          ref={(el) => { panel = el; requestAnimationFrame(() => el.querySelector<HTMLElement>("[data-entry]")?.focus()); }}
          onFocusOut={(event) => {
            if (!panel?.contains(event.relatedTarget as Node | null)) setOpen(false);
          }}
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              event.preventDefault();
              close();
              return;
            }
            // The round stays inside: a panel that let TAB walk out of its last field would
            // close on the author for reaching the end of it.
            if (event.key !== "Tab") return;
            const round = stops();
            const at = round.indexOf(document.activeElement as HTMLElement);
            if (at === -1 || round.length === 0) return;
            const next = event.shiftKey ? at - 1 : at + 1;
            if (next >= 0 && next < round.length) return;
            event.preventDefault();
            round[event.shiftKey ? round.length - 1 : 0].focus();
          }}
          class={[
            "absolute left-0 z-20 w-96 max-w-[90vw] rounded-sm border border-border bg-card p-2 shadow-sm",
            above() ? "bottom-full mb-1" : "top-full mt-1",
          ]}
        >
          <p class="mb-1 text-detail tracking-wider text-muted-foreground uppercase">
            what a new card starts with
          </p>
          <For each={fields()}>
            {(field) => (
              <Show
                when={field.single}
                fallback={
                  <SelectorField
                    itemNode={field.node}
                    defs={props.defs}
                    label={field.key}
                    value={presets[field.key] ?? []}
                    onChange={(items) => keep(field.key, items)}
                  />
                }
              >
                <SelectorField
                  single
                  itemNode={field.node}
                  defs={props.defs}
                  label={field.key}
                  value={presets[field.key]}
                  onChange={(item) => keep(field.key, item)}
                />
              </Show>
            )}
          </For>
        </div>
      </Show>
    </div>
  );
}
