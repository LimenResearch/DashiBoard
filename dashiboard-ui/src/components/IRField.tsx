import { For, Show } from "solid-js";
import type { Element as JSXElement } from "solid-js";
import { Input } from "./Input";
import { SelectorField } from "./SelectorField";
import { widgetFor, type Defs, type IRNode, type Widget } from "../ir";

// The recursive renderer: one component per IR node, dispatching on the widget descriptor
// `widgetFor` returns. Decisions section 13 is what makes this a switch over a closed set
// rather than an attempt to recover intent from JSON Schema keywords.
//
// Select and multiselect use native controls rather than the choices.js `Combobox`. That is
// deliberate and temporary: 08-frontend-rebuild.md records the Combobox rebuilding its whole
// option list on every selection, and wiring the renderer to it before that resync is hardened
// would bake the flicker into every field. Both sit behind the same descriptor, so swapping is
// a one-component change. A native `<select multiple>` also shows every option without typing,
// which was the original complaint about the old select.

type IRFieldProps = {
  node: IRNode;
  defs: Defs;
  label: string;
  required?: boolean;
  value: unknown;
  onChange: (value: unknown) => void;
};

const asRecord = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};

const asArray = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);

/** Options round-trip through the DOM as strings; give the caller back the original type. */
function optionByString(options: (string | number)[], raw: string): string | number {
  return options.find((option) => String(option) === raw) ?? raw;
}

function Label(props: { for?: string; text: string; required?: boolean }) {
  return (
    <label for={props.for} class="text-control-xs font-semibold text-primary">
      <Show when={props.required}>
        <span aria-hidden="true" title="required">
          *{" "}
        </span>
      </Show>
      {props.text}
    </label>
  );
}

/**
 * A field that resolves in one control — pick from a list, or type a value.
 *
 * Label and control share a line. Stacked, each of these cost two rows and a card of eight
 * settings became a column of sixteen, which is most of why the form read as long.
 */
function Row(props: {
  for?: string;
  label: string;
  required?: boolean;
  children: JSXElement;
}) {
  return (
    <div class="flex flex-wrap items-center gap-2">
      <span class="w-36 shrink-0">
        <Label for={props.for} text={props.label} required={props.required} />
      </span>
      {props.children}
    </div>
  );
}

/**
 * A field that needs a component to resolve — a nested object, a variant with its own branch, a
 * multi-selection, the variable picker.
 *
 * `<details>` rather than a signal: the disclosure, the keyboard path and the ARIA state all come
 * from the element, and one less piece of state is one less thing to get wrong. Open by default —
 * the ask was that these fold away, not that they start hidden, and a form whose contents are
 * invisible until clicked is worse than a long one.
 */
function Collapsible(props: { label: string; required?: boolean; children: JSXElement }) {
  return (
    <details open class="group rounded-sm border border-border">
      <summary class="flex cursor-pointer list-none items-center gap-1.5 rounded-sm px-2 py-1 hover:bg-muted [&::-webkit-details-marker]:hidden">
        <span
          aria-hidden="true"
          class="text-muted-foreground transition-transform group-open:rotate-90"
        >
          ▶
        </span>
        <Label text={props.label} required={props.required} />
      </summary>
      <div class="flex flex-col gap-2 px-2 pt-1 pb-2">{props.children}</div>
    </details>
  );
}

export function IRField(props: IRFieldProps) {
  const widget = (): Widget => widgetFor(props.node, props.defs);

  return (
    <Show when={widget()} keyed>
      {(w: Widget) => {
        switch (w.kind) {
          // A container: render its properties in declaration order, each writing its own key
          // back into the object this field holds.
          case "object": {
            const fields = () => (
              <For each={w.properties}>
                {(entry) => (
                  <IRField
                    node={entry.value}
                    defs={props.defs}
                    label={entry.key}
                    required={entry.required}
                    value={asRecord(props.value)[entry.key]}
                    onChange={(inner) =>
                      props.onChange({ ...asRecord(props.value), [entry.key]: inner })
                    }
                  />
                )}
              </For>
            );
            // The card itself is the outermost object and already sits in a bordered panel with
            // its own header, so wrapping it again would be a box inside an identical box.
            return (
              <Show
                when={w.title === undefined}
                fallback={<div class="flex flex-col gap-2">{fields()}</div>}
              >
                <Collapsible label={props.label} required={props.required}>
                  {fields()}
                </Collapsible>
              </Show>
            );
          }

          // A discriminated union: pick an option, then fill in that option's own fields. The
          // value is one object carrying `type` plus the chosen branch's keys.
          case "variant": {
            const chosen = () =>
              (asRecord(props.value).type as string | undefined) ?? w.default ?? w.options[0];
            return (
              <Collapsible label={props.label} required={props.required}>
                <Row for={`${props.label}-variant`} label="type">
                  <select
                    id={`${props.label}-variant`}
                    class="h-control-xs rounded-sm border border-border px-2 text-control-xs"
                    value={chosen()}
                    onChange={(event) => props.onChange({ type: event.currentTarget.value })}
                  >
                    <For each={w.options}>{(option) => <option value={option}>{option}</option>}</For>
                  </select>
                </Row>
                <Show when={w.objects[chosen()]} keyed>
                  {(branch: IRNode) => (
                    <IRField
                      node={branch}
                      defs={props.defs}
                      label={props.label}
                      value={props.value}
                      onChange={(inner) => props.onChange({ ...asRecord(inner), type: chosen() })}
                    />
                  )}
                </Show>
              </Collapsible>
            );
          }

          case "select":
            return (
              <Row for={props.label} label={props.label} required={props.required}>
                <select
                  id={props.label}
                  class="h-control-xs rounded-sm border border-border px-2 text-control-xs"
                  value={String(props.value ?? w.default ?? "")}
                  onChange={(event) =>
                    props.onChange(optionByString(w.options, event.currentTarget.value))
                  }
                >
                  <For each={w.options}>
                    {(option) => <option value={String(option)}>{option}</option>}
                  </For>
                </select>
              </Row>
            );

          case "multiselect":
            return (
              <Collapsible label={props.label} required={props.required}>
                <select
                  id={props.label}
                  multiple
                  size={Math.min(w.options.length, 8)}
                  class="my-1 h-control-xs w-full rounded-sm border border-border px-2 text-control-xs"
                  onChange={(event) =>
                    props.onChange(
                      [...event.currentTarget.selectedOptions].map((option) =>
                        optionByString(w.options, option.value),
                      ),
                    )
                  }
                >
                  <For each={w.options}>
                    {(option) => (
                      <option
                        value={String(option)}
                        selected={asArray(props.value).some((v) => String(v) === String(option))}
                      >
                        {option}
                      </option>
                    )}
                  </For>
                </select>
              </Collapsible>
            );

          case "number":
            return (
              <Row for={props.label} label={props.label} required={props.required}>
                <Input
                  id={props.label}
                  type="number"
                  required={props.required}
                  min={w.min ?? w.exclusiveMin}
                  max={w.max ?? w.exclusiveMax}
                  step={w.integer ? 1 : undefined}
                  value={props.value === undefined ? undefined : String(props.value)}
                  onChange={(event) => {
                    const raw = (event.currentTarget as HTMLInputElement).value;
                    const parsed = w.integer ? parseInt(raw, 10) : parseFloat(raw);
                    props.onChange(Number.isNaN(parsed) ? null : parsed);
                  }}
                />
              </Row>
            );

          case "toggle":
            return (
              <Row label={props.label} required={props.required}>
                <input
                  type="checkbox"
                  class="accent-primary"
                  aria-label={props.label}
                  checked={(props.value as boolean | undefined) ?? w.default ?? false}
                  onChange={(event) => props.onChange(event.currentTarget.checked)}
                />
              </Row>
            );

          case "text":
            return (
              <Row for={props.label} label={props.label} required={props.required}>
                <Input
                  id={props.label}
                  type="text"
                  required={props.required}
                  value={props.value === undefined ? undefined : String(props.value)}
                  onChange={(event) =>
                    props.onChange((event.currentTarget as HTMLInputElement).value)
                  }
                />
              </Row>
            );

          case "repeater": {
            // A repeater over selector items is the variable picker (C2), not a generic list:
            // its items are grouped by qualification rather than shown one per row.
            if (widgetFor(w.items, props.defs).kind === "selector") {
              return (
                <SelectorField
                  itemNode={w.items}
                  defs={props.defs}
                  label={props.label}
                  value={props.value}
                  onChange={(items) => props.onChange(items)}
                />
              );
            }
            return (
              <Collapsible label={props.label} required={props.required}>
                <For each={asArray(props.value)}>
                  {(item, index) => (
                    <IRField
                      node={w.items}
                      defs={props.defs}
                      label={`${props.label}[${index()}]`}
                      value={item}
                      onChange={(inner) => {
                        const next = [...asArray(props.value)];
                        next[index()] = inner;
                        props.onChange(next);
                      }}
                    />
                  )}
                </For>
              </Collapsible>
            );
          }

          // The IR does not constrain this field, so there is nothing honest to draw. Saying so
          // beats a JSON textarea that invites input the schema will reject — and it makes the
          // gap visible where it belongs. Reachable today only through glm's formula, where
          // Pipelines uses ArrayIR{Any}() with a "make more specific" TODO.
          case "unknown":
            return (
              <Row label={props.label} required={props.required}>
                <p class="text-control-xs text-muted-foreground italic">
                  not described by the schema yet
                </p>
              </Row>
            );
        }
      }}
    </Show>
  );
}
