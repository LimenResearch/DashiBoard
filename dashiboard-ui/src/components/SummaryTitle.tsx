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
        <span class="font-mono text-control-xs">
          {props.name || <span class="text-destructive italic">unnamed</span>}
        </span>
      </span>
      <StateDot state={props.state} />
    </span>
  );
}
