// The dot that says where a thing stands with the server: amber until asked, then green or red on
// what it answered, amber again once the thing is edited. Cards and groups each drew their own
// copy, and the run is a third thing with the same three states — which is when a copy becomes a
// component.
//
// It carries no opinion about *what* was asked: the caller decides the state, and says in
// `titles` what each one means for it when the card's wording does not fit.

export type DotState = "unconfirmed" | "confirmed" | "rejected";

const TITLES: Record<DotState, string> = {
  unconfirmed: "not confirmed yet",
  confirmed: "confirmed",
  rejected: "the server found something wrong — open to see what",
};

type StateDotProps = {
  state: DotState;
  /** Hover text per state, where it differs from a card's. */
  titles?: Partial<Record<DotState, string>>;
  /** Which dot this is, as `data-dot`, for a page that has several kinds (a test's handle). */
  name?: string;
};

export function StateDot(props: StateDotProps) {
  return (
    <span
      data-dot={props.name}
      data-state={props.state}
      aria-label={props.state}
      title={props.titles?.[props.state] ?? TITLES[props.state]}
      class={[
        "ml-1 h-2 w-2 shrink-0 rounded-full",
        {
          "bg-success": props.state === "confirmed",
          "bg-destructive": props.state === "rejected",
          "bg-warning": props.state === "unconfirmed",
        },
      ]}
    />
  );
}
