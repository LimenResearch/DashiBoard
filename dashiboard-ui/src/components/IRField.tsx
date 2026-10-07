import { createMemo, For, Show } from "solid-js";
import type { Element as JSXElement } from "solid-js";

import { Disclosure } from "./Disclosure";
import { Input } from "./Input";
import { ConfigurationPicker } from "./ConfigurationPicker";
import { MapField } from "./MapField";
import { plainColumns, pruneMap, transformRows } from "../transformRows";
import { SelectorField } from "./SelectorField";
import type { SelectorRow } from "../selector";
import { carryShared, conditionalOptions, defaultsFor, resolveRef, widgetFor, type Defs, type IRNode, type Widget } from "../ir";

// The recursive renderer: one component per IR node, dispatching on the widget descriptor
// `widgetFor` returns — a switch over a closed set rather than an attempt to recover intent from
// JSON Schema keywords.
//
// Select and multiselect use native controls rather than the choices.js `Combobox`. That is
// deliberate and temporary: the `Combobox` rebuilds its whole option list on every selection, and
// wiring the renderer to it before that is hardened would bake the flicker into every field. Both
// sit behind the same descriptor, so swapping is a one-component change. A native `<select multiple>` also shows every option without typing,
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
  /** Handed to every selector below: which nodes a chain may pass through next. */
  chainFor?: (row: SelectorRow, all: string[]) => string[];
  /** Handed to every selector below: which products a chain step may be narrowed to. */
  productsFor?: (token: string, row: SelectorRow) => string[];
  /** Handed to every selector below: the products a node writes by name. */
  productsOf?: (id: string) => string[];
  /**
   * Handed to every map field below: the columns the card's list `name` resolved to, as the
   * server said — `null` when it has not.
   */
  listsFor?: (name: string) => string[] | null;
  /** Handed to every map field below: the entries of the card's map `field` the server refused. */
  refusedFor?: (field: string) => string[];
  /** Handed to every map field below: whether a column is categorical, where that is known. */
  isCategorical?: (column: string) => boolean;
  /** Handed to every variant below whose options are files: the text of the file behind a name. */
  configurationText?: (kind: string, name: string) => string | null;
  /** Handed to the same: ask the server for the files again. */
  refreshConfigurations?: () => void;
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
            // A choice that hung on a sibling does not outlive the sibling's change: left in
            // place it would be refused at a control that may no longer be drawn.
            const write = (key: string, inner: unknown) => {
              const next = { ...asRecord(props.value), [key]: inner };
              // Emptied is absent: a key left holding nothing would still read as set.
              if (inner === undefined) delete next[key];
              for (const other of w().properties) {
                if (other.key === key) continue;
                const allowed = conditionalOptions(resolveRef(props.node, props.defs), other.key, next);
                const held = next[other.key];
                if (allowed === undefined || !Array.isArray(held)) continue;
                if (allowed === null || !held.every((v) => allowed.includes(String(v)))) delete next[other.key];
              }
              // A plain column taken out of a list takes its entry in the list's map with it.
              for (const other of w().properties) {
                const map = widgetFor(other.value, props.defs);
                if (map.kind !== "map" || map.keysFrom !== key) continue;
                const pruned = pruneMap(
                  next[other.key] as Record<string, string> | undefined,
                  plainColumns(asRecord(props.value)[key]), plainColumns(inner),
                );
                if (pruned === undefined) delete next[other.key];
                else next[other.key] = pruned;
              }
              props.onChange(next);
            };
            const fields = () => (
              <For each={w().properties} keyed={(entry) => entry.key}>
                {(entry) => {
                  // A property whose options hang on a sibling's choice — the fields a
                  // streamliner may select, given its model.
                  const allowed = () =>
                    conditionalOptions(resolveRef(props.node, props.defs), entry().key, asRecord(props.value));
                  // With one option, or none applying yet, there is nothing to choose.
                  const hidden = () => {
                    const a = allowed();
                    return a === null || (a !== undefined && a.length <= 1);
                  };
                  const node = () => {
                    const a = allowed();
                    return a ? { ...entry().value, items: { type: "string", enum: a } } : entry().value;
                  };
                  // Absent means every option, so that is what an untouched field shows.
                  const value = () => {
                    const a = allowed();
                    const held = asRecord(props.value)[entry().key];
                    return a && held === undefined ? a : held;
                  };
                  // A map is drawn beside the list its keys come from, a row per column.
                  const map = () => {
                    const widget = widgetFor(entry().value, props.defs);
                    return widget.kind === "map" ? widget : null;
                  };
                  return (
                    <Show when={!hidden()}>
                      <Show
                        when={map()}
                        keyed
                        fallback={
                      <IRField
                        chainFor={props.chainFor}
                        productsFor={props.productsFor}
                        productsOf={props.productsOf}
                        listsFor={props.listsFor}
                        refusedFor={props.refusedFor}
                        isCategorical={props.isCategorical}
                        configurationText={props.configurationText}
                        refreshConfigurations={props.refreshConfigurations}
                        node={node()}
                        defs={props.defs}
                        label={entry().key}
                        required={entry().required}
                        idPrefix={id()}
                        value={value()}
                        onChange={(inner) => write(entry().key, inner)}
                      />
                        }
                      >
                        {(m: Extract<Widget, { kind: "map" }>) => {
                          const list = m.keysFrom ?? "";
                          const held = () => asRecord(asRecord(props.value)[entry().key]) as Record<string, string>;
                          const rows = () => transformRows(
                            props.listsFor?.(list) ?? null, plainColumns(asRecord(props.value)[list]), held(),
                            props.refusedFor?.(entry().key) ?? [],
                          );
                          return (
                            <MapField
                              label={entry().key}
                              id={`${id()}-${entry().key}`}
                              listName={list}
                              columns={rows().live}
                              stale={rows().stale}
                              values={m.values}
                              held={held()}
                              fixed={(column) => props.isCategorical?.(column) ?? false}
                              onChange={(next) => write(entry().key, next)}
                            />
                          );
                        }}
                      </Show>
                    </Show>
                  );
                }}
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
            // A lone option is not a question: where nothing has been written yet it counts as
            // chosen, whatever the IR's default. A value that is there and names no option has
            // to be asked, since the server will want the name.
            const sole = () => (w().options.length === 1 ? w().options[0] : undefined);
            const untouched = () => props.value === undefined || props.value === null;
            const picked = () =>
              (asRecord(props.value).type as string | undefined) ?? w().default ?? (untouched() ? sole() : undefined);
            const unasked = () => picked() === undefined;
            const chosen = () => picked() ?? "";
            // The chooser is left out only when the one option is the one in hand — a document
            // naming an option this server does not have still needs somewhere to be put right.
            const lone = () => sole() !== undefined && picked() === sole();
            const foreign = () => !unasked() && !w().options.includes(chosen());
            // The blank option is the one meant when none is named, so the document does not
            // name it.
            const named = (inner: unknown, option: string) => {
              const { type: _, ...rest } = asRecord(inner);
              return option === "" ? rest : { ...rest, type: option };
            };
            const branchWidget = () => {
              const branch = w().objects[chosen()];
              return branch === undefined ? undefined : widgetFor(branch, props.defs);
            };
            // One option that takes no settings leaves nothing to show — unless the option is a
            // file, which is itself worth showing.
            const nothing = () => {
              const b = branchWidget();
              return w().optionsFrom === undefined && lone() && b !== undefined && b.kind === "object" && b.properties.length === 0;
            };
            return (
              <Show when={!nothing()}>
              <Collapsible label={props.label} required={props.required}>
                <Show when={w().optionsFrom !== undefined}>
                  <Row for={`${id()}-variant`} label="type">
                    <ConfigurationPicker
                      id={`${id()}-variant`}
                      kind={w().optionsFrom!}
                      options={w().options}
                      chosen={unasked() ? undefined : chosen()}
                      text={(name) => props.configurationText?.(w().optionsFrom!, name) ?? null}
                      onChoose={(option) => {
                        const branch = w().objects[option];
                        const inner = branch === undefined ? undefined : carryShared(props.value, branch, props.defs);
                        props.onChange(named(inner, option));
                      }}
                      onRefresh={() => props.refreshConfigurations?.()}
                    />
                  </Row>
                </Show>
                <Show when={!lone() && w().optionsFrom === undefined}>
                <Row for={`${id()}-variant`} label="type">
                  <select
                    id={`${id()}-variant`}
                    class={[
                      "h-control-xs rounded-sm border px-2 text-control-xs",
                      { "border-border": !unasked() && !foreign(), "border-warning": unasked() || foreign() },
                    ]}
                    value={chosen()}
                    onChange={(event) => {
                      // The branch's own defaults come with the choice. Writing `{type}` alone
                      // left a form showing defaults the document did not hold — and after the
                      // IR fix that lets `dissimilarity` name `euclidean`, those defaults exist
                      // to be carried.
                      const option = event.currentTarget.value;
                      const branch = w().objects[option];
                      // What both branches declare is kept, so a change of type does not throw
                      // away what was already filled in (`carryShared`).
                      const inner = branch === undefined ? undefined : carryShared(props.value, branch, props.defs);
                      props.onChange(named(inner, option));
                    }}
                  >
                    <Show when={unasked()}>
                      <option value="" disabled>
                        choose…
                      </option>
                    </Show>
                    <Show when={foreign()}>
                      <option value={chosen()} disabled>
                        {chosen()} — not available
                      </option>
                    </Show>
                    <For each={w().options}>
                      {(option) => <option value={option}>{option === "" ? "default" : option}</option>}
                    </For>
                  </select>
                </Row>
                </Show>
                <Show when={!unasked() && w().objects[chosen()]}>
                  <IRField
                    chainFor={props.chainFor}
                    productsFor={props.productsFor}
                    productsOf={props.productsOf}
                    listsFor={props.listsFor}
                    refusedFor={props.refusedFor}
                    isCategorical={props.isCategorical}
                    configurationText={props.configurationText}
                    refreshConfigurations={props.refreshConfigurations}
                    node={w().objects[chosen()]!}
                    defs={props.defs}
                    label={props.label}
                    inline
                    idPrefix={id()}
                    value={props.value}
                    onChange={(inner) => props.onChange(named(inner, chosen()))}
                  />
                </Show>
              </Collapsible>
              </Show>
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
            const taken = (option: string | number) =>
              asArray(props.value).some((v) => String(v) === String(option));
            // Written in the order offered, so pressing pills in another order changes nothing.
            const toggle = (option: string | number) =>
              props.onChange(w().options.filter((o) => (o === option ? !taken(o) : taken(o))));
            return (
              <Collapsible label={props.label} required={props.required}>
                {/* Every option is a pill, on or off: what is taken reads without scrolling. */}
                <div id={id()} role="group" aria-label={props.label} class="my-1 flex flex-wrap gap-1.5">
                  <For each={w().options}>
                    {(option) => (
                      <button
                        type="button"
                        data-option={String(option)}
                        aria-pressed={taken(option) ? "true" : "false"}
                        onClick={() => toggle(option)}
                        class={[
                          "inline-flex h-6 items-center rounded-full border px-2.5 font-mono text-control-xs hover:border-primary",
                          taken(option)
                            ? "border-primary bg-primary/15 font-medium text-primary"
                            : "border-border bg-card text-muted-foreground",
                        ]}
                      >
                        {option}
                      </button>
                    )}
                  </For>
                </div>
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
            // A repeater over selector items is the variable picker, not a generic list:
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
                          chainFor={props.chainFor}
                          productsFor={props.productsFor}
                          productsOf={props.productsOf}
                          listsFor={props.listsFor}
                          refusedFor={props.refusedFor}
                          isCategorical={props.isCategorical}
                          configurationText={props.configurationText}
                          refreshConfigurations={props.refreshConfigurations}
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
                  chainFor={props.chainFor}
                  productsFor={props.productsFor}
                  productsOf={props.productsOf}
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
          // case for it, so the form drew nothing and two required fields could not be filled in
          // from the UI at all. The server resolves such a field with
          // `only(...)`, exactly one column; the picker in `single` mode holds exactly one row.
          case "selector":
            return (
              <SelectorField
                chainFor={props.chainFor}
                productsFor={props.productsFor}
                productsOf={props.productsOf}
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
          // A map belongs beside the list its keys come from, so its object draws it; alone it
          // has no columns to offer a row for.
          case "map":
            return null;

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
