import { For, Show } from "solid-js";

// One tab strip, used for the page's stages and for a picker's selector kinds.
//
// Extracted because it was about to be published as two components. The design system is the
// place a duplicate stops being a local convenience and becomes a second definition of the same
// thing — two strips that drift apart is exactly what a system exists to prevent.

export type TabSize = "sm" | "md";

// C8: keyed on the union, never on `string`. Add a size and this fails to build rather than
// resolving to `undefined` and silently rendering an unstyled tab — the shape that painted 12 of
// 22 nodes black next door.
const SIZING: Record<TabSize, string> = {
  sm: "px-3 py-1 text-control-xs",
  md: "px-4 py-2 text-control-xs",
};

type TabsProps<T extends string> = {
  /** Names the strip in the DOM. A picker's kind tabs sit inside a page whose stages are also
   *  tabs, so without a group name a query for one strip selects both. */
  group: string;
  items: readonly T[];
  active: T;
  onSelect: (item: T) => void;
  /** A count to show on the tab. Only the open tab's panel is rendered, so a selection inside a
   *  closed one would otherwise be invisible. Omit for strips where that cannot happen. */
  count?: (item: T) => number;
  size?: TabSize;
};

export function Tabs<T extends string>(props: TabsProps<T>) {
  return (
    <div role="tablist" data-tabs={props.group} class="flex gap-1.5 border-b border-border">
      <For each={props.items}>
        {(item) => {
          const count = () => props.count?.(item) ?? 0;
          return (
            <button
              type="button"
              role="tab"
              data-tab={item}
              aria-selected={props.active === item ? "true" : "false"}
              onClick={() => props.onSelect(item)}
              class={[
                "-mb-px rounded-t-sm border border-b-0",
                SIZING[props.size ?? "sm"],
                {
                  "border-border bg-background font-semibold text-primary": props.active === item,
                  "border-transparent text-muted-foreground hover:text-foreground":
                    props.active !== item,
                },
              ]}
            >
              {item}
              <Show when={count() > 0}>
                <span class="ml-1 rounded-full bg-accent px-1.5 text-detail text-accent-foreground">
                  {count()}
                </span>
              </Show>
            </button>
          );
        }}
      </For>
    </div>
  );
}
