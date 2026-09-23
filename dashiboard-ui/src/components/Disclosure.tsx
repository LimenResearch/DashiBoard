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

/**
 * Points at where the content will appear; a 90° turn is a movement you can see.
 *
 * Turned by a rule in App.css keyed on the *nearest* `details`, not by `group-open`. Tailwind's
 * group variant compiles to `:is(.group:is([open]) *)`, which matches any descendant of any open
 * group — so every nested chevron turned when an outer disclosure opened and then sat stuck,
 * because its own state was never what the selector read.
 */
export function Chevron(props: { /** For a fold that is not a `<details>`, which turns it itself. */ turned?: boolean }) {
  return (
    <svg
      viewBox="0 0 12 12"
      aria-hidden="true"
      class={[
        "disclosure-chevron h-3 w-3 shrink-0 text-muted-foreground transition-transform duration-150",
        { "rotate-90": props.turned === true },
      ]}
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
  /** Told when it folds or unfolds, for a host that draws something of its own to match. */
  onToggle?: (open: boolean) => void;
  class?: string;
  /** Override the default guide-rule indent — a card body sits in its own panel already. */
  bodyClass?: string;
};

/**
 * Bring what just unfolded into view: centred, or — for the last item of the pipeline, marked
 * `data-last-item` — ending at the bottom of the view, just above the sticky row of actions,
 * which is on screen regardless. Content taller than the view keeps its top on screen.
 * Unfolding lengthens the page below the hand, so without this the new content can lie
 * entirely off screen.
 */
export function showUnfolded(element: Element) {
  requestAnimationFrame(() => {
    const rect = element.getBoundingClientRect();
    const sticky = document.querySelector("[data-add]")?.getBoundingClientRect().height ?? 0;
    const view = window.innerHeight - sticky;
    const top = element.closest("[data-last-item]") !== null
      ? rect.bottom - view
      : rect.height > view ? rect.top - 8 : rect.top + rect.height / 2 - view / 2;
    // The page's scroller, which a test DOM leaves without `scrollBy`; the window's would log there.
    (document.scrollingElement ?? document.documentElement).scrollBy?.({ top, behavior: "smooth" });
  });
}

export function Disclosure(props: DisclosureProps) {
  return (
    <details
      open={props.open ?? false}
      onToggle={(event) => {
        if (event.currentTarget.open) showUnfolded(event.currentTarget);
        props.onToggle?.(event.currentTarget.open);
      }}
      class={props.class ?? ""}
    >
      {/* Wraps: a long title (a card named after a long type) used to push the actions past the
          column's edge; folded to a second line, they stay in the pane. */}
      <summary class="flex flex-wrap cursor-pointer list-none items-center gap-1.5 rounded-sm py-0.5 hover:bg-muted [&::-webkit-details-marker]:hidden">
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
