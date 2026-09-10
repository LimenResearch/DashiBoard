import { createSignal, Show } from "solid-js";

function buttonClassList(active: boolean) {
  return {
    "text-primary": true,
    "text-xs": true,
    "font-semibold": true,
    "border-b-2": !active,
    "border-border": true,
    "hover:bg-secondary": true,
    "w-full": true,
    "text-left": true,
  };
}

function notificationClassList(modified: boolean) {
  return {
    "float-right": true,
    "p-3": true,
    "inline-block": true,
    "hover:text-destructive/60": true,
    invisible: !modified,
  };
}

type TogglerProps = {
  name: string;
  modified: boolean;
  onReset: (e: Event) => void;
  children: any;
};

export function Toggler(props: TogglerProps) {
  const [active, setActive] = createSignal(false);
  let notification!: HTMLSpanElement;
  const onButtonClick = (e: Event) =>
    notification.isEqualNode(e.target as Node) || setActive(!active());
  return (
    <div>
      <button class={buttonClassList(active())} onClick={onButtonClick}>
        <span class="pl-4 py-2 inline-block">{props.name}</span>
        <span
          ref={notification}
          class={notificationClassList(props.modified)}
          onClick={props.onReset}
        >
          ⬤
        </span>
      </button>
      <Show when={active()}>
        <div class="p-3 bg-card rounded-b-sm border-b-2">{props.children}</div>
      </Show>
    </div>
  );
}
