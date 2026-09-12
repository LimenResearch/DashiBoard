import { createSignal, Show } from "solid-js";
import type { Element as JSXElement } from "solid-js";

// A named, collapsible panel — one filter's control, in the Filter stage.
//
// The reset dot used to be a `<span onClick>` *inside* the toggle button. That is interactive
// content nested in a button, which is invalid HTML, unreachable by keyboard, and forced an
// `isEqualNode` check to work out which of the two had been clicked. As siblings each control
// does one thing, and the check disappears rather than being made more careful.
//
// Reset is offered only when there is something to reset. Previously it was always rendered and
// merely `invisible` — which keeps it in the tab order and readable by assistive tech while
// looking absent.

type TogglerProps = {
  name: string;
  modified: boolean;
  onReset: (e: Event) => void;
  children: JSXElement;
};

export function Toggler(props: TogglerProps) {
  const [open, setOpen] = createSignal(false);

  return (
    <div>
      <div class="flex items-center border-b-2 border-border">
        <button
          type="button"
          class="w-full flex-1 px-2 py-1.5 text-left text-control-xs font-semibold text-primary hover:bg-secondary"
          aria-expanded={open() ? "true" : "false"}
          onClick={() => setOpen(!open())}
        >
          {props.name}
        </button>
        <Show when={props.modified}>
          <button
            type="button"
            aria-label={`reset ${props.name}`}
            title={`reset ${props.name}`}
            class="px-2 py-1.5 text-control-xs text-muted-foreground hover:text-destructive"
            onClick={(e) => props.onReset(e)}
          >
            ⬤
          </button>
        </Show>
      </div>
      <Show when={open()}>
        <div class="rounded-b-sm border-b-2 border-border bg-card p-3">{props.children}</div>
      </Show>
    </div>
  );
}
