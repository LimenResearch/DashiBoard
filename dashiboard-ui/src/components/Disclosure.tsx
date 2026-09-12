import type { Element as JSXElement } from "solid-js";

// A folding section, used for card fields, whole cards and whole groups.
//
// `<details>` rather than a signal: the disclosure, the keyboard path and the ARIA state all come
// from the element, and one less piece of state is one less thing to get wrong.
//
// Closed by default. That reverses an earlier call of mine — I argued a form whose contents are
// hidden until clicked is worse than a long one, and with four levels of nesting on a cluster card
// the long one turned out to be unreadable. Folded, a card is one line naming what it is, which is
// what makes a pipeline of six of them scannable.

/** Points at where the content will appear; a 90° turn is a movement you can see. A filled
 *  triangle at this size reads as a bullet whatever its angle. */
export function Chevron() {
  return (
    <svg
      viewBox="0 0 12 12"
      aria-hidden="true"
      class="h-3 w-3 shrink-0 text-muted-foreground transition-transform duration-150 group-open:rotate-90"
    >
      <path
        d="M4.5 2.5 L8 6 L4.5 9.5"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  );
}

type DisclosureProps = {
  /** The one line shown when folded. Say what the thing *is*, since this is all that survives. */
  summary: JSXElement;
  children: JSXElement;
  open?: boolean;
  class?: string;
  /** Override the default guide-rule indent — a card body sits in its own panel already. */
  bodyClass?: string;
};

export function Disclosure(props: DisclosureProps) {
  return (
    <details open={props.open ?? false} class={["group", props.class ?? ""]}>
      <summary class="flex cursor-pointer list-none items-center gap-1.5 rounded-sm py-0.5 hover:bg-muted [&::-webkit-details-marker]:hidden">
        <Chevron />
        {props.summary}
      </summary>
      <div class={props.bodyClass ?? "ml-1.5 flex flex-col gap-0.5 border-l border-border pl-3"}>
        {props.children}
      </div>
    </details>
  );
}

/**
 * An action that lives on the folded line — Remove, typically.
 *
 * A click inside `<summary>` toggles the disclosure, so anything actionable there has to say it
 * handled the event itself. Without this, deleting a card also expands it on the way out.
 */
export function summaryAction(run: () => void) {
  return (event: MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();
    run();
  };
}
