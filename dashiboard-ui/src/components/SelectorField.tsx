import { createMemo, createSignal, For, Show } from "solid-js";

import { Chevron } from "./Disclosure";
import { SelectorHelp } from "./SelectorHelp";
import { Tabs } from "./Tabs";
import {
  asItems,
  chainKey,
  collapse,
  documentText,
  expand,
  type SelectorItem,
  type SelectorRow,
} from "../selector";
import { widgetFor, type Defs, type IRNode } from "../ir";
import { emptyEntry, engaged, stageOf, step, suggestions, type EntryInput } from "../selectorEntry";
import * as _ from "lodash";

// The variable picker (C2), built to study 05.
//
// A field is a list of items, and a value may appear in it more than once qualified differently —
// case E, which is what rules out modelling the field as a set of values with attributes. The
// layout that reads best for the *vocabularies* is one tabbed list per kind, and the naive version
// of that fails exactly there: a row is a value, and a value appears once.
//
// The repair is what a row *holds*. It is not a value with a qualification, it is a value with a
// **list** of them. Switch a value on and it has to say `direct` or `through`, with nothing
// assumed; once it carries one, `+` adds another. Case E becomes one click rather than
// unrepresentable.
//
// One thing this deliberately does not do: compute resolved column names. Suffix concatenation is
// DashiBoard's rule and a copy here is a second source of truth (A10, and C2's second constraint
// withdrawn 2026-09-12). The writes strip shows the document, never a resolved name.
//
// It does keep reordering. Cases append, so document order is the order the author built it in —
// but §12's positional `weights` rule reads that order, and neither the tabbed rows nor the strip
// can change it once set, because rows are grouped by vocabulary and cross-kind order is not
// something a grouped view can express. Hence the chip row.

type SelectorFieldProps = {
  /** The IR for one item — a `$defs/variable` node. */
  itemNode: IRNode;
  defs: Defs;
  label: string;
  /** Marks the name with `*`. */
  required?: boolean;
  /** Given, the host folds the panel — a group's own line does — and no fold control is drawn. */
  open?: boolean;
  /** Narrows `all`, the nodes `through` accepts, to those a chain may pass through next after `row`. */
  chainFor?: (row: SelectorRow, all: string[]) => string[];
  value: unknown;
} & (
  | { single?: false; onChange: (items: SelectorItem[]) => void }
  /**
   * One item, not a list: a lone `$defs/variable` field — `partition`, `weights`, `interp.input`.
   * The server resolves such a field with `only(...)` (`Pipelines/src/group_api/deps.jl`), so it
   * must come out as exactly one column, and the same picker enforces that by holding one row: a
   * second pick replaces the first, switching the value off empties the field (`undefined`, which
   * the export drops — `partition = nothing`). The order strip and the `+` for a second
   * qualification are list affordances and are not drawn.
   */
  | { single: true; onChange: (item: SelectorItem | undefined) => void }
);

/**
 * Display order. The *set* comes from the schema's `oneOf`; only left-to-right is ours: nodes and
 * groups first, since a document that has them is mostly written in them.
 */
const KIND_ORDER = ["nodes", "groups", "cols"];

/** A selection as it is typed and as its chip reads: `cols:PRES@impute@zscore`. */
export const chipText = (row: SelectorRow) =>
  `${row.kind}:${row.value}${row.chain.map((node) => `@${node}`).join("")}`;

export function SelectorField(props: SelectorFieldProps) {
  const widget = createMemo(() => widgetFor(props.itemNode, props.defs));

  const kinds = createMemo(() => {
    const w = widget();
    if (w.kind !== "selector") return [] as string[];
    const rank = (k: string) => {
      const at = KIND_ORDER.indexOf(k);
      return at === -1 ? KIND_ORDER.length : at;
    };
    return [...w.kinds].sort((a, b) => rank(a) - rank(b));
  });

  const optionsOf = (kind: string) => {
    const w = widget();
    return w.kind === "selector" ? (w.options[kind] ?? []).map(String) : [];
  };

  /** The tabs drawn: a kind with nothing to offer has no tab. `kinds()` stays the model's. */
  const tabKinds = createMemo(() => kinds().filter((kind) => optionsOf(kind).length > 0));

  /** The nodes a chain may be built from — the vocabulary `through` itself accepts. */
  const chainOptions = () => {
    const w = widget();
    if (w.kind !== "selector") return [] as string[];
    const through = widgetFor(w.through, props.defs);
    return through.kind === "multiselect" ? through.options.map(String) : [];
  };

  // One item is read as a one-item list; the boundary is `write`, which hands one back.
  const items = () =>
    props.single === true
      ? props.value === undefined || props.value === null ? [] : [props.value as SelectorItem]
      : asItems(props.value);
  const rows = createMemo(() => expand(items(), kinds()));
  const casesFor = (kind: string, value: string) =>
    rows().filter((r) => r.kind === kind && r.value === value).map((r) => r.chain);

  const write = (next: SelectorRow[]) => {
    if (props.single === true) {
      // Cases append, so the newest row is the last one — it is what the author just chose.
      const kept = next.slice(-1);
      props.onChange(kept.length === 0 ? undefined : collapse(kept)[0]);
    } else {
      props.onChange(collapse(next));
    }
  };

  /** Cases append, so document order is the order the author built it in. */
  const addCase = (kind: string, value: string, chain: string[]) =>
    write([...rows(), { kind, value, chain }]);

  const removeCase = (kind: string, value: string, chain: string[]) => {
    const key = chainKey(chain);
    let dropped = false;
    write(
      rows().filter((r) => {
        if (dropped || r.kind !== kind || r.value !== value || chainKey(r.chain) !== key) return true;
        dropped = true;
        return false;
      }),
    );
  };

  // --- control state, which is not document state ---------------------------
  const [picked, setPicked] = createSignal<string | null>(null);
  // Values switched on but not yet specified. A list, because switching on a second value should
  // not silently abandon the first one's unanswered question.
  const [pending, setPending] = createSignal<string[]>([]);
  // One composer at a time: building a chain is a focused activity, and two half-built chains on
  // screen is a state nobody meant to be in.
  const [composing, setComposing] = createSignal<{ key: string; chain: string[] } | null>(null);
  // Native drag is not keyboard reachable, which is why the chips carry arrow buttons as well.
  const [dragging, setDragging] = createSignal<number | null>(null);

  const idOf = (kind: string, value: string) => `${kind}:${value}`;
  const isPending = (id: string) => pending().includes(id);
  const chainBeingBuilt = (id: string) => {
    const c = composing();
    return c !== null && c.key === id ? c.chain : null;
  };
  const clearPending = (id: string) => setPending(pending().filter((p) => p !== id));

  // --- the typed entry: the panel's steps, from the keyboard -----------------
  // Closed until the box is in hand.
  const [entry, setEntry] = createSignal({ ...emptyEntry, open: false });
  /** The chain steps on offer after `row`: the host's say, else every node. */
  const chainFor = (row: SelectorRow) => {
    const narrow = props.chainFor;
    return narrow === undefined ? chainOptions() : narrow(row, chainOptions());
  };
  const vocabulary = createMemo(() => {
    const e = entry();
    return {
      kinds: tabKinds(),
      options: Object.fromEntries(tabKinds().map((kind) => [kind, optionsOf(kind)])),
      chain: e.kind !== null && e.name !== null ? chainFor({ kind: e.kind, value: e.name, chain: e.chain }) : chainOptions(),
    };
  });
  const listId = _.uniqueId("selector-list-");
  let root: HTMLDivElement | undefined;
  let box: HTMLInputElement | undefined;

  const tokens = () => {
    const e = entry();
    return [
      ...(e.kind === null ? [] : [`${e.kind}:`]),
      ...(e.name === null ? [] : [e.name]),
      ...e.chain.map((node) => `@${node}`),
    ];
  };

  /** One step of the grammar; a finished entry is written unless the field already holds it. */
  const apply = (input: EntryInput) => {
    const result = step(entry(), input, vocabulary(), props.single === true);
    setEntry(result.state);
    const row = result.emit;
    if (row !== undefined && !casesFor(row.kind, row.value).some((c) => chainKey(c) === chainKey(row.chain)))
      write([...rows(), row]);
    return result;
  };

  // --- chips by keyboard ------------------------------------------------------
  const chipAt = (index: number) =>
    root?.querySelectorAll<HTMLElement>("[data-chip]")[index];

  const onChipKey = (event: KeyboardEvent, index: number, row: SelectorRow) => {
    const last = rows().length - 1;
    const arrow = event.key === "ArrowLeft" ? -1 : event.key === "ArrowRight" ? 1 : 0;
    if (arrow !== 0 && event.altKey) {
      event.preventDefault();
      if (props.single === true) return;
      reorder(index, index + arrow);
      // The list redraws around the moved chip; the focus goes with it.
      const label = chipText(row);
      requestAnimationFrame(() => root?.querySelector<HTMLElement>(`[data-chip="${CSS.escape(label)}"]`)?.focus());
    } else if (arrow !== 0) {
      event.preventDefault();
      if (index + arrow > last) box?.focus();
      else chipAt(Math.max(0, index + arrow))?.focus();
    } else if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault();
      (index > 0 ? chipAt(index - 1) : box)?.focus();
      removeCase(row.kind, row.value, row.chain);
    } else if (event.key === "Escape" || (event.key === "Tab" && !event.shiftKey)) {
      event.preventDefault();
      box?.focus();
    }
  };

  const onEntryKey = (event: KeyboardEvent) => {
    // With nothing typed, going left — or back — lands on the last chip.
    const back = event.key === "ArrowLeft" || (event.key === "Tab" && event.shiftKey);
    if (back && entry().text === "" && rows().length > 0) {
      event.preventDefault();
      chipAt(rows().length - 1)?.focus();
      return;
    }
    const inputs: Record<string, EntryInput> = {
      Enter: { type: "enter" }, Escape: { type: "escape" },
      ArrowDown: { type: "down" }, ArrowUp: { type: "up" },
    };
    if (event.key === "Tab" && !event.shiftKey) {
      // TAB completes only while a list is open; otherwise it leaves the field, as TAB does.
      if (apply({ type: "tab" }).leave !== true) event.preventDefault();
    } else if (event.key === "Backspace" && entry().text === "") {
      event.preventDefault();
      apply({ type: "backspace" });
    } else if (event.key in inputs) {
      event.preventDefault();
      apply(inputs[event.key]);
      requestAnimationFrame(() =>
        root?.querySelector("[data-highlighted]")?.scrollIntoView?.({ block: "nearest" }));
    }
  };

  const highlightedId = (index: number) =>
    entry().open && engaged(entry()) && entry().highlight === index ? true : undefined;

  const openKind = () => {
    // The box and the panel are one list: a kind token selects the tab.
    const typed = entry().kind;
    if (typed !== null && tabKinds().includes(typed)) return typed;
    const chosen = picked();
    return chosen !== null && tabKinds().includes(chosen) ? chosen : (tabKinds()[0] ?? "");
  };

  // The name, the chips and the text box are always on screen; this folds what is below them.
  const [unfolded, setOpen] = createSignal(false);
  const open = () => props.open ?? unfolded();
  const panelId = _.uniqueId("selector-panel-");

  /** The open tab's rows, narrowed by what is being typed for that kind. */
  const panelValues = () => {
    const e = entry();
    return e.kind === openKind() && stageOf(e) === "name"
      ? suggestions(e, vocabulary())
      : optionsOf(openKind());
  };

  /** The matches for the part being typed; each carries the panel's two words for the mouse. */
  const SuggestionList = () => (
    <ul
      id={listId}
      role="listbox"
      aria-label={`${props.label} suggestions`}
      // Keeps the focus in the box while the mouse picks.
      onMouseDown={(event) => event.preventDefault()}
      class={open()
        ? "flex flex-col p-1"
        : "absolute z-10 mt-1 max-h-56 w-full overflow-y-auto rounded-sm border border-border bg-card p-1 shadow-sm"}
    >
      <For each={suggestions(entry(), vocabulary())} fallback={
        <li class="p-1 text-control-xs text-muted-foreground italic">nothing matches</li>
      }>
        {(value, i) => {
          const atKind = () => stageOf(entry()) === "kind";
          return (
            <li
              data-suggestion={value}
              data-highlighted={highlightedId(i())}
              role="option"
              id={`${listId}-${i()}`}
              aria-selected={highlightedId(i()) ? "true" : "false"}
              onClick={() => { if (atKind()) apply({ type: "pick", value, how: "continue" }); }}
              class={[
                "flex items-center gap-2 rounded-sm px-1.5 py-0.5 font-mono text-control-xs",
                { "bg-accent/60": highlightedId(i()) === true, "cursor-pointer": atKind() },
              ]}
            >
              <span class="min-w-0 grow truncate">{atKind() ? `${value}:` : value}</span>
              <Show when={!atKind()}>
                <button
                  type="button"
                  tabindex={-1}
                  data-pick="direct"
                  onClick={() => apply({ type: "pick", value, how: "direct" })}
                  class="inline-flex h-5 items-center rounded-full border border-border bg-card px-2 font-sans hover:border-primary hover:text-primary"
                >
                  direct
                </button>
                <button
                  type="button"
                  tabindex={-1}
                  data-pick="through"
                  disabled={chainOptions().length === 0}
                  onClick={() => apply({ type: "pick", value, how: "through" })}
                  class="inline-flex h-5 items-center rounded-full border border-border bg-card px-2 font-sans hover:border-primary hover:text-primary disabled:opacity-40"
                >
                  through…
                </button>
              </Show>
            </li>
          );
        }}
      </For>
    </ul>
  );

  /**
   * Whether another qualification could be specified at all.
   *
   * `direct` is available until taken; `through` needs at least one node to build a chain from,
   * and a document with no nodes yet has none. When neither route is open there is nothing to
   * offer, so the `+` is withheld rather than opening a panel whose every option is disabled.
   */
  const canAddCase = (kind: string, value: string) =>
    !casesFor(kind, value).some((c) => c.length === 0) || chainOptions().length > 0;

  /** On means: carries a qualification, or is part-way through choosing one. */
  const isLive = (kind: string, value: string) => {
    const id = idOf(kind, value);
    return Boolean(casesFor(kind, value).length || isPending(id) || chainBeingBuilt(id));
  };

  const reorder = (from: number, to: number) => {
    const next = [...rows()];
    if (to < 0 || to >= next.length || from === to) return;
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    write(next);
  };

  function switchOff(kind: string, value: string) {
    const id = idOf(kind, value);
    clearPending(id);
    if (chainBeingBuilt(id) !== null) setComposing(null);
    write(rows().filter((r) => !(r.kind === kind && r.value === value)));
  }

  const name = () => (
    <span data-selector-name class="text-control-xs font-semibold text-primary">
      {props.label}
      <Show when={props.required}>
        <span class="ml-0.5 text-muted-foreground" title="required">*</span>
      </Show>
    </span>
  );
  /** Under its own chevron the body is indented on a guide rule, as a `Disclosure` body is. */
  const indent = () => (props.open === undefined ? "ml-1.5 border-l border-border pl-3" : "");

  return (
    <div data-selector ref={(el) => { root = el; }} class="flex flex-col gap-1">
      {/* Always on screen: the name, what is selected, and (below) the text box. One chip per
          value, in document order — the order positional rules read — so the chips are also where
          a value is moved or removed. */}
      {/* The line of a folding field, as `Disclosure` draws it, so this one's chevron and name
          sit where its siblings' do. */}
      <div class="flex flex-wrap items-center gap-1.5 py-0.5">
        <Show when={props.open === undefined} fallback={name()}>
          <button
            type="button"
            data-fold
            aria-expanded={open() ? "true" : "false"}
            aria-controls={panelId}
            aria-label={`${open() ? "fold" : "unfold"} the choices for ${props.label}`}
            onClick={() => setOpen(!open())}
            class="flex items-center gap-1.5 rounded-sm hover:bg-muted"
          >
            <Chevron turned={open()} />
            {name()}
          </button>
        </Show>
        <ul class="flex min-w-0 flex-wrap gap-1" aria-label={`${props.label} selection`}>
          <For each={rows()}>
            {(r, i) => {
              const label = () => chipText(r);
              return (
                <li
                  data-chip={label()}
                  tabindex={-1}
                  onKeyDown={(event) => onChipKey(event, i(), r)}
                  draggable={props.single === true ? undefined : "true"}
                  onDragStart={() => setDragging(i())}
                  onDragOver={(event) => event.preventDefault()}
                  onDrop={() => {
                    // The dragged chip moves to *this* position: `from` is the source, `i()` the target.
                    const from = dragging();
                    if (from !== null) reorder(from, i());
                    setDragging(null);
                  }}
                  class={[
                    "inline-flex h-5 items-center gap-1 rounded-sm pr-0.5 pl-2 font-mono text-control-xs",
                    "focus:outline focus:outline-1 focus:outline-primary",
                    "border border-border bg-background",
                  ]}
                >
                  <span>{label()}</span>
                  <span class="flex">
                    {/* One item has no order to change. */}
                    <Show when={props.single !== true}>
                      <For each={[["earlier", -1] as const, ["later", 1] as const]}>
                        {([dir, delta]) => (
                          <button
                            type="button"
                            data-move={dir}
                            aria-label={`move ${label()} ${dir}`}
                            disabled={delta < 0 ? i() === 0 : i() === rows().length - 1}
                            onClick={() => reorder(i(), i() + delta)}
                            class="grid h-4 w-4 place-items-center rounded-sm text-muted-foreground hover:bg-secondary hover:text-foreground disabled:opacity-30"
                          >
                            {delta < 0 ? "←" : "→"}
                          </button>
                        )}
                      </For>
                    </Show>
                    {/* With the panel folded this is the only way to take a value out. */}
                    <button
                      type="button"
                      data-chip-remove
                      data-remove
                      aria-label={`remove ${label()}`}
                      onClick={() => removeCase(r.kind, r.value, r.chain)}
                      class="grid h-4 w-4 place-items-center rounded-sm text-muted-foreground hover:bg-destructive/15 hover:text-destructive"
                    >
                      ×
                    </button>
                  </span>
                </li>
              );
            }}
          </For>
        </ul>
      </div>

      <div class={["flex items-start gap-1.5", indent()]}>
        <SelectorHelp single={props.single} />
        <div class="relative min-w-0 grow">
          <div
            onClick={() => box?.focus()}
            class="flex cursor-text flex-wrap items-center gap-1 rounded-sm border border-border px-1.5 py-1 focus-within:border-primary"
          >
            <For each={tokens()}>
              {(token) => (
                <span data-token class="rounded-sm bg-accent/60 px-1 font-mono text-control-xs">{token}</span>
              )}
            </For>
            <input
              ref={(el) => { box = el; }}
              data-entry
              role="combobox"
              aria-expanded={entry().open ? "true" : "false"}
              aria-controls={open() ? panelId : listId}
              aria-activedescendant={entry().open && engaged(entry()) ? `${listId}-${entry().highlight}` : undefined}
              aria-autocomplete="list"
              aria-label={`${props.label}, type a selection`}
              autocomplete="off"
              spellcheck={false}
              placeholder={tokens().length === 0 ? "nodes: name @node, then Enter" : ""}
              value={entry().text}
              onInput={(event) => apply({ type: "text", value: event.currentTarget.value })}
              onKeyDown={onEntryKey}
              onFocus={() => apply({ type: "focus" })}
              onBlur={() => { if (entry().open) setEntry({ ...entry(), open: false }); }}
              class="min-w-24 grow bg-transparent font-mono text-control-xs outline-none"
            />
          </div>
          {/* With the panel open, the panel is the list. */}
          <Show when={entry().open && !open()}>
            <SuggestionList />
          </Show>
        </div>
      </div>

      <div data-panel id={panelId} hidden={!open()} class={["flex flex-col gap-2", indent()]}>
      {/*
        What the field will be written as — the selector form, never a resolved name. Rendered
        from `documentText` rather than assembled here, so the format has one definition; showing
        it while editing makes the control's effect on the document visible before a save.
      */}
      <div class="rounded-sm border border-primary/20 bg-primary/5 px-2 py-1.5">
        <span class="mr-2 text-detail tracking-wider text-muted-foreground uppercase">writes</span>
        <span class="font-mono text-control-xs break-words text-foreground">
          {/* A lone field with nothing in it is absent from the document, not an empty list. */}
          {props.single === true && rows().length === 0 ? "not set" : documentText(rows())}
        </span>
      </div>

      <div class="rounded-sm border border-border">
        <Tabs
          group="kinds"
          items={tabKinds()}
          active={openKind()}
          onSelect={(kind) => {
            setPicked(kind);
            // A tab chosen by hand takes the box with it, or the kind token would hold the old tab.
            if (entry().kind !== null) setEntry({ ...emptyEntry, kind });
          }}
          count={(kind) => optionsOf(kind).filter((v) => casesFor(kind, v).length > 0).length}
        />

        <div class="max-h-64 overflow-y-auto p-1">
          <Show when={stageOf(entry()) === "chain" && open()}>
            <SuggestionList />
          </Show>
          <Show
            when={stageOf(entry()) !== "chain" && panelValues().length > 0}
            fallback={
              <Show when={stageOf(entry()) !== "chain"}>
                <p class="p-2 text-control-xs text-muted-foreground italic">
                  {optionsOf(openKind()).length > 0 ? "nothing matches" : "none defined"}
                </p>
              </Show>
            }
          >
            <For each={panelValues()}>
              {(value, at) => {
                const kind = () => openKind();
                const id = () => idOf(kind(), value);
                const cases = () => casesFor(kind(), value);
                const on = () => isLive(kind(), value);
                const hasDirect = () => cases().some((c) => c.length === 0);

                return (
                  <div
                    data-value={value}
                    id={`${listId}-${at()}`}
                    data-highlighted={entry().kind === kind() ? highlightedId(at()) : undefined}
                    class={[
                      "flex flex-col gap-1 rounded-sm px-1.5 py-1",
                      { "bg-accent/40": on(), "hover:bg-muted": !on() },
                      "data-[highlighted]:outline data-[highlighted]:outline-1 data-[highlighted]:outline-primary",
                    ]}
                  >
                    <div class="flex flex-wrap items-center gap-2">
                      {/*
                        A switch rather than a checkbox: a checkbox says "included", and this says
                        "has something to specify". Inline rather than extracted — a primitive with
                        one use is a guess about the second.
                      */}
                      <button
                        type="button"
                        role="switch"
                        aria-checked={on() ? "true" : "false"}
                        aria-label={`select ${value}`}
                        onClick={() => {
                          if (on()) switchOff(kind(), value);
                          else setPending([...pending(), id()]);
                        }}
                        class={[
                          "relative h-4 w-7 flex-none rounded-full border transition-colors",
                          { "border-primary bg-primary": on(), "border-border bg-secondary": !on() },
                        ]}
                      >
                        <span
                          class={[
                            "absolute top-px left-px h-3 w-3 rounded-full bg-card transition-transform",
                            { "translate-x-3": on() },
                          ]}
                        />
                      </button>

                      <span
                        class={["font-mono text-control-xs", { "font-medium text-primary": on() }]}
                      >
                        {value}
                      </span>

                      {/* Qualifications sit on the value's own line — a second line per selected
                          value costs more height than this layout is chosen for. */}
                      <For each={cases()}>
                        {(chain) => (
                          <span
                            data-case={chain.length === 0 ? "direct" : chain.join("→")}
                            class="inline-flex h-5 items-center gap-1.5 rounded-full border border-primary/35 bg-primary/10 pr-0.5 pl-2 font-mono text-control-xs"
                          >
                            <span class="text-accent-foreground">
                              {chain.length === 0 ? "direct" : chain.map((node) => `@${node}`).join("")}
                            </span>
                            <button
                              type="button"
                              aria-label={`remove ${chain.length === 0 ? "direct" : chain.join("→")} for ${value}`}
                              onClick={() => removeCase(kind(), value, chain)}
                              class="grid h-4 w-4 place-items-center rounded-full text-muted-foreground hover:bg-destructive/15 hover:text-destructive"
                            >
                              ×
                            </button>
                          </span>
                        )}
                      </For>

                      {/* The + is the repair: it is what lets a value hold more than one
                          qualification, and so what makes case E expressible at all. */}
                      <Show
                        when={
                          props.single !== true &&
                          cases().length > 0 &&
                          !isPending(id()) &&
                          chainBeingBuilt(id()) === null &&
                          canAddCase(kind(), value)
                        }
                      >
                        <button
                          type="button"
                          data-add-case={value}
                          aria-label={`add another qualification for ${value}`}
                          title="add another qualification"
                          onClick={() => setPending([...pending(), id()])}
                          class="grid h-5 w-5 place-items-center rounded-full border border-dashed border-border text-muted-foreground hover:border-solid hover:border-primary hover:bg-accent/60 hover:text-primary"
                        >
                          +
                        </button>
                      </Show>

                      {/* Nothing is assumed. A value switched on with no qualification is visibly
                          unfinished, so the control asks rather than defaulting to direct. */}
                      <Show when={isPending(id())}>
                        <span class="ml-auto inline-flex items-center gap-1 rounded-full border border-warning/45 bg-warning/10 p-0.5">
                          <span class="px-1 text-detail font-semibold tracking-wider text-warning uppercase">
                            specify
                          </span>
                          <button
                            type="button"
                            data-specify="direct"
                            disabled={hasDirect()}
                            onClick={() => {
                              addCase(kind(), value, []);
                              clearPending(id());
                            }}
                            class="inline-flex h-5 items-center rounded-full border border-border bg-card px-2 text-control-xs hover:border-primary hover:text-primary disabled:opacity-40"
                          >
                            direct
                          </button>
                          {/* A chain is built from nodes, so with none defined there is nothing to
                              build one out of. Offered as unreachable rather than as a route that
                              opens an empty composer. */}
                          <button
                            type="button"
                            data-specify="through"
                            disabled={chainOptions().length === 0}
                            title={
                              chainOptions().length === 0
                                ? "no nodes defined yet — a pass-through is built from them"
                                : undefined
                            }
                            onClick={() => {
                              clearPending(id());
                              setComposing({ key: id(), chain: [] });
                            }}
                            class="inline-flex h-5 items-center rounded-full border border-border bg-card px-2 text-control-xs hover:border-primary hover:text-primary disabled:opacity-40 disabled:hover:border-border disabled:hover:text-inherit"
                          >
                            through…
                          </button>
                        </span>
                      </Show>
                    </div>

                    <Show when={chainBeingBuilt(id())} keyed>
                      {(chain: string[]) => (
                        <div
                          data-chain-builder
                          class="ml-9 flex flex-wrap items-center gap-1.5 rounded-sm border border-dashed border-primary/45 bg-primary/5 px-2 py-1.5"
                        >
                          <span class="text-detail tracking-wider text-muted-foreground uppercase">
                            add a pass-through
                          </span>
                          <For each={chainFor({ kind: kind(), value, chain })}>
                            {(node) => (
                              <button
                                type="button"
                                onClick={() => setComposing({ key: id(), chain: [...chain, node] })}
                                class="inline-flex h-5 items-center rounded-full border border-border bg-card px-2 font-mono text-control-xs hover:border-primary hover:text-primary"
                              >
                                {node}
                              </button>
                            )}
                          </For>
                          <span class="ml-auto font-mono text-control-xs">
                            <Show
                              when={chain.length > 0}
                              fallback={
                                <span class="text-muted-foreground">
                                  pick a node — order matters
                                </span>
                              }
                            >
                              <span class="font-medium text-primary">{chain.join(" → ")}</span>
                            </Show>
                          </span>
                          <Show when={chain.length > 0}>
                            <button
                              type="button"
                              data-chain="commit"
                              disabled={cases().some((c) => chainKey(c) === chainKey(chain))}
                              onClick={() => {
                                addCase(kind(), value, chain);
                                setComposing(null);
                              }}
                              class="inline-flex h-control-xs items-center rounded-sm bg-accent px-2.5 text-control-xs font-semibold text-accent-foreground disabled:opacity-50"
                            >
                              {cases().some((c) => chainKey(c) === chainKey(chain))
                                ? "already added"
                                : "add"}
                            </button>
                          </Show>
                          <button
                            type="button"
                            data-chain="cancel"
                            onClick={() => {
                              setComposing(null);
                              if (cases().length === 0) clearPending(id());
                            }}
                            class="inline-flex h-control-xs items-center rounded-sm px-2 text-control-xs text-muted-foreground hover:bg-secondary hover:text-foreground"
                          >
                            cancel
                          </button>
                        </div>
                      )}
                    </Show>
                  </div>
                );
              }}
            </For>
          </Show>
        </div>
      </div>
      </div>
    </div>
  );
}
