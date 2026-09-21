import { createMemo, For, Show } from "solid-js";
import type { Element as JSXElement } from "solid-js";

import { Disclosure } from "./Disclosure";
import { Input } from "./Input";
import { SelectorField } from "./SelectorField";
import { defaultsFor, widgetFor, type Defs, type IRNode, type Widget } from "../ir";

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
  /**
   * This object's caller has already drawn the container its fields belong in, so render them
   * bare. True for a variant's chosen branch: `{type: "dbscan", radius: …}` is one flat object
   * and one disclosure, not a `method` inside a `method`.
   */
  inline?: boolean;
  /** Prefix for every id below this field, so two cards of one type do not collide. */
  idPrefix?: string;
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
      {props.text}
      {/* After the name, not before it, and muted: required is an annotation on the field rather
          than part of what the field is called. Leading `* ` read as if the asterisk were the
          first character of every other label. */}
      <Show when={props.required}>
        <span class="ml-0.5 text-muted-foreground" title="required">
          *
        </span>
      </Show>
    </label>
  );
}

/**
 * A field that resolves in one control — pick from a list, or type a value.
 *
 * Label and control share a line, with the labels in a fixed column so the controls line up down
 * the form. Stacked, each of these cost two rows and a card of eight settings read as a column of
 * sixteen.
 */
function Row(props: {
  for?: string;
  label: string;
  required?: boolean;
  children: JSXElement;
}) {
  return (
    <div class="flex flex-wrap items-center gap-2 py-0.5">
      <span class="w-32 shrink-0">
        <Label for={props.for} text={props.label} required={props.required} />
      </span>
      {props.children}
    </div>
  );
}

/**
 * A field that needs a component to resolve — a nested object, a variant with its branch, a
 * multi-selection, the variable picker.
 *
 * Indentation carries the nesting, the way it does in YAML: one guide rule per level, and a
 * child's chevron sits exactly where a sibling row's label sits. The previous version drew a box
 * per level, whose border and padding pushed each nested label a few pixels further right than
 * the rows beside it — so depth was visible but the alignment said nothing.
 *
 * `<details>` rather than a signal: the disclosure, the keyboard path and the ARIA state all come
 * from the element. Open by default, since the ask was that these fold away rather than start
 * hidden.
 */
function Collapsible(props: { label: string; required?: boolean; children: JSXElement }) {
  return (
    <Disclosure summary={<Label text={props.label} required={props.required} />}>
      {props.children}
    </Disclosure>
  );
}

export function IRField(props: IRFieldProps) {
  const widget = (): Widget => widgetFor(props.node, props.defs);
  const id = () => (props.idPrefix ? `${props.idPrefix}-${props.label}` : props.label);

  return (
    // Keyed on the *kind*, not the descriptor. `widgetFor` returns a fresh object on every
    // evaluation, and keying on it remounted this whole subtree whenever `props.defs` changed —
    // which is every IR refetch, i.e. every time a column, group or node name changed anywhere.
    // A field only needs rebuilding when it becomes a different kind of control; everything else
    // it reads reactively through `w()`.
    <Show when={widget().kind} keyed>
      {(kind: Widget["kind"]) => {
        // `Extract<Widget, { kind: typeof kind }>` would need to be recomputed inside each case
        // to narrow past this point — `kind` isn't narrowed yet here, before the switch — so each
        // case below declares its own `w`, narrowed to that case's literal kind.
        switch (kind) {
          // A container: render its properties in declaration order, each writing its own key
          // back into the object this field holds.
          case "object": {
            // `Extract<Widget, { kind: typeof kind }>` above is computed before the switch
            // narrows `kind`, so it resolves against the full `Widget["kind"]` union rather than
            // this one case — re-narrow locally, per the brief's note on this step.
            const w = () => widget() as Extract<Widget, { kind: "object" }>;
            // Keyed on the property's *name*, not the entry object. The IR is refetched wholesale
            // on every vocabulary change, so `w().properties` is a fresh array of fresh entries
            // every time even when no property actually changed — reference-keying (`<For>`'s
            // default) would remount every field in every card on every refetch, which is the
            // same bug this file's outer `Show` was just fixed for, one level down.
            const fields = () => (
              <For each={w().properties} keyed={(entry) => entry.key}>
                {(entry) => (
                  <IRField
                    node={entry().value}
                    defs={props.defs}
                    label={entry().key}
                    required={entry().required}
                    idPrefix={id()}
                    value={asRecord(props.value)[entry().key]}
                    onChange={(inner) =>
                      props.onChange({ ...asRecord(props.value), [entry().key]: inner })
                    }
                  />
                )}
              </For>
            );
            // Two objects render bare. The card is the outermost one and already sits in a
            // bordered panel with its own header, so wrapping it again would be a box inside an
            // identical box — that is what `title` marks. A variant's branch is the other: its
            // caller drew the disclosure, and a second one repeating the same label put every
            // branch field a level deeper than the `type` row it belongs beside.
            const bare = () => props.inline === true || w().title !== undefined;
            return (
              <Show
                when={!bare()}
                fallback={<div class="flex flex-col gap-0.5">{fields()}</div>}
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
            // Re-narrowed locally — see the comment in `case "object"`.
            const w = () => widget() as Extract<Widget, { kind: "variant" }>;
            // No fallback to `options[0]`. That list arrives from a Julia `Dict`, so its order
            // carries no intent — preselecting from it asserts a choice nobody made, and the
            // document then disagrees with the form about whether the question was answered.
            const chosen = () =>
              (asRecord(props.value).type as string | undefined) ?? w().default ?? "";
            return (
              <Collapsible label={props.label} required={props.required}>
                <Row for={`${id()}-variant`} label="type">
                  <select
                    id={`${id()}-variant`}
                    class={[
                      "h-control-xs rounded-sm border px-2 text-control-xs",
                      { "border-border": chosen() !== "", "border-warning": chosen() === "" },
                    ]}
                    value={chosen()}
                    onChange={(event) => {
                      // The branch's own defaults come with the choice. Writing `{type}` alone
                      // left a form showing defaults the document did not hold — and after the
                      // IR fix that lets `dissimilarity` name `euclidean`, those defaults exist
                      // to be carried.
                      const option = event.currentTarget.value;
                      const branch = w().objects[option];
                      const inner = branch === undefined ? undefined : defaultsFor(branch, props.defs);
                      props.onChange({ ...(inner as object), type: option });
                    }}
                  >
                    <Show when={chosen() === ""}>
                      <option value="" disabled>
                        choose…
                      </option>
                    </Show>
                    <For each={w().options}>{(option) => <option value={option}>{option}</option>}</For>
                  </select>
                </Row>
                <Show when={w().objects[chosen()]}>
                  <IRField
                    node={w().objects[chosen()]!}
                    defs={props.defs}
                    label={props.label}
                    inline
                    idPrefix={id()}
                    value={props.value}
                    onChange={(inner) => props.onChange({ ...asRecord(inner), type: chosen() })}
                  />
                </Show>
              </Collapsible>
            );
          }

          case "select": {
            // Re-narrowed locally — see the comment in `case "object"`.
            const w = () => widget() as Extract<Widget, { kind: "select" }>;
            return (
              <Row for={id()} label={props.label} required={props.required}>
                <select
                  id={id()}
                  class="h-control-xs rounded-sm border border-border px-2 text-control-xs"
                  value={String(props.value ?? w().default ?? "")}
                  onChange={(event) =>
                    props.onChange(optionByString(w().options, event.currentTarget.value))
                  }
                >
                  <For each={w().options}>
                    {(option) => <option value={String(option)}>{option}</option>}
                  </For>
                </select>
              </Row>
            );
          }

          case "multiselect": {
            // Re-narrowed locally — see the comment in `case "object"`.
            const w = () => widget() as Extract<Widget, { kind: "multiselect" }>;
            return (
              <Collapsible label={props.label} required={props.required}>
                <select
                  id={id()}
                  multiple
                  size={Math.min(w().options.length, 8)}
                  class="my-1 h-control-xs w-full rounded-sm border border-border px-2 text-control-xs"
                  onChange={(event) =>
                    props.onChange(
                      [...event.currentTarget.selectedOptions].map((option) =>
                        optionByString(w().options, option.value),
                      ),
                    )
                  }
                >
                  <For each={w().options}>
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
          }

          case "number": {
            // Re-narrowed locally — see the comment in `case "object"`.
            const w = () => widget() as Extract<Widget, { kind: "number" }>;
            return (
              <Row for={id()} label={props.label} required={props.required}>
                <Input
                  id={id()}
                  type="number"
                  required={props.required}
                  min={w().min ?? w().exclusiveMin}
                  max={w().max ?? w().exclusiveMax}
                  step={w().integer ? 1 : undefined}
                  value={props.value === undefined ? undefined : String(props.value)}
                  onChange={(event) => {
                    const raw = (event.currentTarget as HTMLInputElement).value;
                    const parsed = w().integer ? parseInt(raw, 10) : parseFloat(raw);
                    props.onChange(Number.isNaN(parsed) ? null : parsed);
                  }}
                />
              </Row>
            );
          }

          case "toggle": {
            // Re-narrowed locally — see the comment in `case "object"`.
            const w = () => widget() as Extract<Widget, { kind: "toggle" }>;
            return (
              <Row label={props.label} required={props.required}>
                <input
                  type="checkbox"
                  class="accent-primary"
                  aria-label={props.label}
                  checked={(props.value as boolean | undefined) ?? w().default ?? false}
                  onChange={(event) => props.onChange(event.currentTarget.checked)}
                />
              </Row>
            );
          }

          case "text":
            return (
              <Row for={id()} label={props.label} required={props.required}>
                <Input
                  id={id()}
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
            // Re-narrowed locally — see the comment in `case "object"`.
            const w = () => widget() as Extract<Widget, { kind: "repeater" }>;
            // A repeater over selector items is the variable picker (C2), not a generic list:
            // its items are grouped by qualification rather than shown one per row.
            //
            // Decided in a memo and branched in JSX, not with an `if` here: this callback body
            // runs inside the keyed `<Show>` above, which is not a tracking scope, and
            // `widgetFor` walks `props.node` and `props.defs` — around half the suite's
            // untracked-read warnings came from this one line.
            const itemsWidget = createMemo(() => widgetFor(w().items, props.defs));
            return (
              <Show
                when={itemsWidget().kind === "selector"}
                fallback={
                  <Collapsible label={props.label} required={props.required}>
                    <For each={asArray(props.value)}>
                      {(item, index) => (
                        <IRField
                          node={w().items}
                          defs={props.defs}
                          label={`${props.label}[${index()}]`}
                          idPrefix={`${id()}-${index()}`}
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
                }
              >
                {/* No disclosure around it: the picker keeps its name, its chips and its text
                    box on screen and folds the rest itself. */}
                <SelectorField
                  itemNode={w().items}
                  defs={props.defs}
                  label={props.label}
                  required={props.required}
                  value={props.value}
                  onChange={(items) => props.onChange(items)}
                />
              </Show>
            );
          }

          // A lone `$defs/variable` — `partition`, `weights`, `gaussian_encoding.input`,
          // `interp.input`: one selector item, where a repeater over them is a list. There was no
          // case for it, so the form drew nothing — two required fields could not be filled in
          // from the UI at all (measured 2026-09-17). The server resolves such a field with
          // `only(...)`, exactly one column; the picker in `single` mode holds exactly one row.
          case "selector":
            return (
              <SelectorField
                single
                itemNode={props.node}
                defs={props.defs}
                label={props.label}
                required={props.required}
                value={props.value}
                onChange={(item) => props.onChange(item)}
              />
            );

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
