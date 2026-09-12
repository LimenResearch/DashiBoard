import { createSignal, For, Show } from "solid-js";

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
  value: unknown;
  onChange: (items: SelectorItem[]) => void;
};

/** Display order. The *set* comes from the schema's `oneOf`; only left-to-right is ours. */
const KIND_ORDER = ["cols", "groups", "nodes"];

export function SelectorField(props: SelectorFieldProps) {
  const widget = () => widgetFor(props.itemNode, props.defs);

  const kinds = () => {
    const w = widget();
    if (w.kind !== "selector") return [] as string[];
    const rank = (k: string) => {
      const at = KIND_ORDER.indexOf(k);
      return at === -1 ? KIND_ORDER.length : at;
    };
    return [...w.kinds].sort((a, b) => rank(a) - rank(b));
  };

  const optionsOf = (kind: string) => {
    const w = widget();
    return w.kind === "selector" ? (w.options[kind] ?? []).map(String) : [];
  };

  /** The nodes a chain may be built from — the vocabulary `through` itself accepts. */
  const chainOptions = () => {
    const w = widget();
    if (w.kind !== "selector") return [] as string[];
    const through = widgetFor(w.through, props.defs);
    return through.kind === "multiselect" ? through.options.map(String) : [];
  };

  const rows = () => expand(asItems(props.value), kinds());
  const casesFor = (kind: string, value: string) =>
    rows().filter((r) => r.kind === kind && r.value === value).map((r) => r.chain);

  const write = (next: SelectorRow[]) => props.onChange(collapse(next));

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

  const openKind = () =>
    picked() ?? kinds().find((k) => optionsOf(k).length > 0) ?? kinds()[0] ?? "";

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

  return (
    <div class="my-2 flex flex-col gap-2">
      {/* No heading of its own: every caller already names this field — IRField in the
          disclosure it wraps this in, GroupsEditor in the name field directly above. Two labels
          for one control is how a form starts looking like it was assembled rather than designed. */}
      {/*
        The ordering surface, and the only one.

        Document order matters — §12's positional `weights` rule reads it — and neither the tabbed
        rows nor the writes strip can change it: rows are grouped by vocabulary, so cross-kind
        order is not something either can express. Study 05 showed this row read-only and I nearly
        shipped it that way; six tests exist for the reordering precisely because the panels alone
        cannot do it.

        One chip per *value* rather than per item, which is lossless: one item holding several
        values resolves exactly as several items holding one each (case A ≡ B).
      */}
      <Show when={rows().length > 0}>
        <ul class="flex flex-wrap gap-1" aria-label={`${props.label} order`}>
          <For each={rows()}>
            {(r, i) => {
              const label = () =>
                `${r.kind}:${r.value}` + (r.chain.length ? `·${r.chain.join("→")}` : "");
              return (
                <li
                  data-chip={label()}
                  draggable="true"
                  onDragStart={() => setDragging(i())}
                  onDragOver={(event) => event.preventDefault()}
                  onDrop={() => {
                    // The dragged chip moves to *this* position — `from` is the source, `i()` the
                    // target. Reusing the arrow-button helper here would have spliced the target
                    // out and put it back where it already was.
                    const from = dragging();
                    if (from !== null) reorder(from, i());
                    setDragging(null);
                  }}
                  class="inline-flex h-5 items-center gap-1 rounded-sm border border-border bg-background pr-0.5 pl-2 font-mono text-control-xs"
                >
                  <span>{label()}</span>
                  <span class="flex">
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
                  </span>
                </li>
              );
            }}
          </For>
        </ul>
      </Show>

      {/*
        What the field will be written as — the selector form, never a resolved name. Rendered
        from `documentText` rather than assembled here, so the format has one definition; showing
        it while editing makes the control's effect on the document visible before a save.
      */}
      <div class="rounded-sm border border-primary/20 bg-primary/5 px-2 py-1.5">
        <span class="mr-2 text-detail tracking-wider text-muted-foreground uppercase">writes</span>
        <span class="font-mono text-control-xs break-words text-foreground">
          {documentText(rows())}
        </span>
      </div>

      <div class="rounded-sm border border-border">
        <Tabs
          group="kinds"
          items={kinds()}
          active={openKind()}
          onSelect={setPicked}
          count={(kind) => optionsOf(kind).filter((v) => casesFor(kind, v).length > 0).length}
        />

        <div class="max-h-64 overflow-y-auto p-1">
          <Show
            when={optionsOf(openKind()).length > 0}
            fallback={<p class="p-2 text-control-xs text-muted-foreground italic">none defined</p>}
          >
            <For each={optionsOf(openKind())}>
              {(value) => {
                const kind = () => openKind();
                const id = () => idOf(kind(), value);
                const cases = () => casesFor(kind(), value);
                const on = () => isLive(kind(), value);
                const hasDirect = () => cases().some((c) => c.length === 0);

                return (
                  <div
                    data-value={value}
                    class={[
                      "flex flex-col gap-1 rounded-sm px-1.5 py-1",
                      { "bg-accent/40": on(), "hover:bg-muted": !on() },
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
                              {chain.length === 0 ? "direct" : `through ${chain.join("→")}`}
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
                        when={cases().length > 0 && !isPending(id()) && chainBeingBuilt(id()) === null}
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
                          <button
                            type="button"
                            data-specify="through"
                            onClick={() => {
                              clearPending(id());
                              setComposing({ key: id(), chain: [] });
                            }}
                            class="inline-flex h-5 items-center rounded-full border border-border bg-card px-2 text-control-xs hover:border-primary hover:text-primary"
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
                          <For each={chainOptions()}>
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
  );
}
