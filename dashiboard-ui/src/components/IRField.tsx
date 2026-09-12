import { For, Show } from "solid-js";
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
    <label for={props.for} class="block text-control-xs font-semibold text-primary">
      <Show when={props.required}>
        <span aria-hidden="true">* </span>
      </Show>
      {props.text}
    </label>
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
          case "object":
            return (
              <fieldset class="border-l-2 border-border pl-3">
                <Show when={w.title}>
                  <legend class="text-control-xs text-muted-foreground">{w.title}</legend>
                </Show>
                <For each={w.properties}>
                  {(entry) => (
                    <div class="my-2">
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
                    </div>
                  )}
                </For>
              </fieldset>
            );

          // A discriminated union: pick an option, then fill in that option's own fields. The
          // value is one object carrying `type` plus the chosen branch's keys.
          case "variant": {
            const chosen = () =>
              (asRecord(props.value).type as string | undefined) ?? w.default ?? w.options[0];
            return (
              <div>
                <Label text={props.label} required={props.required} />
                <select
                  class="my-1 h-control-xs rounded-sm border border-border pl-2 text-control-xs"
                  value={chosen()}
                  onChange={(event) =>
                    props.onChange({ type: event.currentTarget.value })
                  }
                >
                  <For each={w.options}>
                    {(option) => <option value={option}>{option}</option>}
                  </For>
                </select>
                <Show when={w.objects[chosen()]} keyed>
                  {(branch: IRNode) => (
                    <IRField
                      node={branch}
                      defs={props.defs}
                      label={props.label}
                      value={props.value}
                      onChange={(inner) =>
                        props.onChange({ ...asRecord(inner), type: chosen() })
                      }
                    />
                  )}
                </Show>
              </div>
            );
          }

          case "select":
            return (
              <div>
                <Label for={props.label} text={props.label} required={props.required} />
                <select
                  id={props.label}
                  class="my-1 h-control-xs rounded-sm border border-border pl-2 text-control-xs"
                  value={String(props.value ?? w.default ?? "")}
                  onChange={(event) =>
                    props.onChange(optionByString(w.options, event.currentTarget.value))
                  }
                >
                  <For each={w.options}>
                    {(option) => <option value={String(option)}>{option}</option>}
                  </For>
                </select>
              </div>
            );

          case "multiselect":
            return (
              <div>
                <Label for={props.label} text={props.label} required={props.required} />
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
              </div>
            );

          case "number":
            return (
              <div>
                <Label for={props.label} text={props.label} required={props.required} />
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
              </div>
            );

          case "toggle":
            return (
              <div>
                <label class="inline-flex items-center text-control-xs font-semibold text-primary">
                  <input
                    type="checkbox"
                    checked={(props.value as boolean | undefined) ?? w.default ?? false}
                    onChange={(event) => props.onChange(event.currentTarget.checked)}
                  />
                  <span class="ml-2">{props.label}</span>
                </label>
              </div>
            );

          case "text":
            return (
              <div>
                <Label for={props.label} text={props.label} required={props.required} />
                <Input
                  id={props.label}
                  type="text"
                  required={props.required}
                  value={props.value === undefined ? undefined : String(props.value)}
                  onChange={(event) =>
                    props.onChange((event.currentTarget as HTMLInputElement).value)
                  }
                />
              </div>
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
              <div>
                <Label text={props.label} required={props.required} />
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
              </div>
            );
          }

          // The IR does not constrain this field, so there is nothing honest to draw. Saying so
          // beats a JSON textarea that invites input the schema will reject — and it makes the
          // gap visible where it belongs. Reachable today only through glm's formula, where
          // Pipelines uses ArrayIR{Any}() with a "make more specific" TODO.
          case "unknown":
            return (
              <div>
                <Label text={props.label} required={props.required} />
                <p class="text-control-xs text-muted-foreground italic">
                  {props.label}: not described by the schema yet
                </p>
              </div>
            );
        }
      }}
    </Show>
  );
}
