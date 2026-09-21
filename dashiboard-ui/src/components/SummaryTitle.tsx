import { Show } from "solid-js";

import { StateDot, type DotState } from "./StateDot";

// The folded line of a card or a group: what kind of thing it is, its name, and where it stands.
// Folded, this is all there is on screen, so the kind has to tell a group from a card and one
// card type from another.

/** `dimensionality_reduction` → `Dimensionality Reduction`, for a type the server gave no title. */
export const readableType = (type: string) =>
  type
    .split("_")
    .filter((word) => word !== "")
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(" ");

type SummaryTitleProps = {
  /** Names the `data-*-title` / `data-*-text` hooks. */
  hook: "card" | "group";
  /** "Group", or the card type's title. */
  kind: string;
  /** Empty means unnamed. */
  name: string;
  state: DotState;
  /** Given, the name is a text box in the line itself: the one place a name is read and changed. */
  edit?: { id: string; label: string; onRename: (field: HTMLInputElement) => void };
};

export function SummaryTitle(props: SummaryTitleProps) {
  // `truncate` sits on the inner text run: `text-overflow: ellipsis` does not render on a flex
  // container, which this outer span has to be for the dot to align.
  return (
    <span
      {...{ [`data-${props.hook}-title`]: "" }}
      title={`${props.kind} : ${props.name || "unnamed"}`}
      class="flex min-w-0 items-center gap-1.5"
    >
      <span {...{ [`data-${props.hook}-text`]: "" }} class="min-w-0 truncate">
        <span class="text-control-xs font-semibold text-primary">{props.kind}</span>
        <span class="text-muted-foreground">:</span>
        <Show when={props.edit === undefined}>
          <span class="font-mono text-control-xs">
            {props.name || <span class="text-destructive italic">unnamed</span>}
          </span>
        </Show>
      </span>
      <Show when={props.edit} keyed>
        {(edit) => (
          <input
            id={edit.id}
            aria-label={edit.label}
            placeholder="unnamed"
            value={props.name}
            // The line is a `<summary>`: a click, or a space typed here, would fold it.
            onClick={(event) => event.preventDefault()}
            onKeyUp={(event) => { if (event.key === " ") event.preventDefault(); }}
            // `change`, not `input`: a rename rewrites every reference to the name.
            onChange={(event) => edit.onRename(event.currentTarget)}
            class="h-control-xs w-40 min-w-0 shrink rounded-sm border border-border bg-transparent px-1.5 font-mono text-control-xs placeholder:text-destructive placeholder:italic"
          />
        )}
      </Show>
      <StateDot state={props.state} />
    </span>
  );
}
