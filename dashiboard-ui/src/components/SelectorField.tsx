import { createSignal, For, Show } from "solid-js";
import { Checkbox } from "./Checkbox";
import { Tabs } from "./Tabs";
import { widgetFor, type Defs, type IRNode } from "../ir";

// The variable picker (C2). A field like `inputs` is an ordered list of *items*, each naming
// exactly one of `nodes`/`groups`/`cols` plus an optional ordered `through` chain.
//
// The panels group by qualification rather than by value, which is what lets the same column
// appear twice — once passed through and once raw — since those land in different sections.
// A layout that treated a field as "a set of values with attributes" has nowhere to put the
// second one. See `06-design.md`, "C2 in detail".
//
// An empty `through` resolves identically to an absent one, so Direct is simply the section whose
// chain is empty: one component, not two.

export type SelectorItem = {
  through?: string[];
  [kind: string]: unknown;
};

type SelectorFieldProps = {
  /** The IR for one item — a `$defs/variable` node. */
  itemNode: IRNode;
  defs: Defs;
  label: string;
  value: unknown;
  onChange: (items: SelectorItem[]) => void;
};

const asItems = (value: unknown): SelectorItem[] =>
  Array.isArray(value) ? (value as SelectorItem[]) : [];

/** Items are grouped by their chain; the key must respect order, since [a,b] ≠ [b,a]. */
const chainKey = (item: SelectorItem) => JSON.stringify(item.through ?? []);

const asList = (value: unknown): string[] =>
  value === undefined ? [] : Array.isArray(value) ? value.map(String) : [String(value)];

/** The distinct chains present, empty first, otherwise in first-appearance order. */
function chains(items: SelectorItem[]): string[][] {
  const seen = new Map<string, string[]>();
  seen.set("[]", []);
  for (const item of items) seen.set(chainKey(item), item.through ?? []);
  return [...seen.values()];
}

export function SelectorField(props: SelectorFieldProps) {
  const widget = () => widgetFor(props.itemNode, props.defs);
  const items = () => asItems(props.value);

  // Sections opened but holding nothing yet. They live here rather than in the document,
  // because `{cols: [], through: [...]}` is valid, resolves to nothing, and is pure noise in
  // the TOML the user is writing. A section earns its place in the document by holding a value.
  const [pending, setPending] = createSignal<string[][]>([]);

  /** Every section on screen: those the document implies, plus those merely opened. */
  const allChains = () => {
    const seen = new Map(chains(items()).map((chain) => [JSON.stringify(chain), chain]));
    for (const chain of pending()) seen.set(JSON.stringify(chain), chain);
    return [...seen.values()];
  };

  // The *set* of kinds is read off the schema's `oneOf` and never invented here. Their left-to-
  // right order is presentation only: `cols` first because it is the common pick, matching the
  // panel order agreed in 06-design.md. A kind not listed keeps its derived position, after these.
  const KIND_ORDER = ["cols", "groups", "nodes"];
  const kindsOf = () => {
    const w = widget();
    if (w.kind !== "selector") return [];
    const rank = (kind: string) => {
      const at = KIND_ORDER.indexOf(kind);
      return at === -1 ? KIND_ORDER.length : at;
    };
    return [...w.kinds].sort((a, b) => rank(a) - rank(b));
  };
  const optionsOf = (kind: string) => {
    const w = widget();
    return w.kind === "selector" ? (w.options[kind] ?? []) : [];
  };
  const chainOptions = () => {
    const w = widget();
    if (w.kind !== "selector") return [];
    const through = widgetFor(w.through, props.defs);
    return through.kind === "multiselect" ? through.options.map(String) : [];
  };

  /** Values currently chosen for one kind within one chain. */
  const chosen = (chain: string[], kind: string) => {
    const key = JSON.stringify(chain);
    return items()
      .filter((item) => chainKey(item) === key)
      .flatMap((item) => asList(item[kind]));
  };

  /**
   * Rebuild the whole list. Emitting one item per (chain, kind) is lossless: one item holding
   * several values resolves identically to several items holding one each — verified, and pinned
   * in `Pipelines/test/groups.jl`. What is *not* interchangeable is items under different chains,
   * which is exactly what the sections keep apart.
   */
  function write(chain: string[], kind: string, values: string[]) {
    const key = JSON.stringify(chain);
    const next: SelectorItem[] = [];
    for (const existing of allChains()) {
      const existingKey = JSON.stringify(existing);
      for (const k of kindsOf()) {
        const vals = existingKey === key && k === kind ? values : chosen(existing, k);
        if (vals.length === 0) continue;
        next.push(existing.length === 0 ? { [k]: vals } : { [k]: vals, through: existing });
      }
    }
    props.onChange(next);
  }

  /** Add or drop one value within a (chain, kind), leaving the rest of the field alone. */
  function toggle(chain: string[], kind: string, value: string, checked: boolean) {
    const current = chosen(chain, kind);
    const next = checked
      ? [...current, value]                      // appended: order within a kind is the user's
      : current.filter((existing) => existing !== value);
    write(chain, kind, next);
  }

  function addChain(chain: string[]) {
    if (chain.length === 0) return;
    setPending([...pending(), chain]);
  }

  // One chip per value, in document order and across kinds.
  //
  // Splitting a multi-value item into one chip each is lossless — one item holding several values
  // resolves identically to several holding one each — while grouping by chain is *not* optional,
  // which is why the chain travels with the chip. Order matters: the resolved column list follows
  // the document, and section 3's positional `weights` rule reads it, so this row is the only
  // place cross-kind order can be expressed. The panels group by qualification and therefore fix
  // it by layout.
  type Chip = { kind: string; value: string; through: string[] };

  const chips = (): Chip[] =>
    items().flatMap((item) =>
      kindsOf().flatMap((kind) =>
        asList(item[kind]).map((value) => ({ kind, value, through: item.through ?? [] })),
      ),
    );

  const chipLabel = (chip: Chip) =>
    `${chip.kind}:${chip.value}` + (chip.through.length > 0 ? `·${chip.through.join("→")}` : "");

  function reorder(from: number, to: number) {
    const list = chips();
    if (to < 0 || to >= list.length || from === to) return;
    const [moved] = list.splice(from, 1);
    list.splice(to, 0, moved);
    props.onChange(
      list.map((chip) =>
        chip.through.length === 0
          ? ({ [chip.kind]: chip.value } as SelectorItem)
          : ({ [chip.kind]: chip.value, through: chip.through } as SelectorItem),
      ),
    );
  }

  const [dragging, setDragging] = createSignal<number | null>(null);
  const [draft, setDraft] = createSignal<string[]>([]);

  /**
   * One qualification — Direct, or Through a chain — with its three vocabularies behind tabs.
   *
   * Tabs rather than three panels side by side: the vocabularies are alternatives (the `oneOf`
   * gate admits exactly one kind per item), and three lists abreast turn into one jumble of
   * checkboxes under three headings. Only the open tab is on screen, so each tab carries the
   * count of what is chosen inside it — otherwise switching away would hide a selection.
   *
   * Rendered as a component so each section owns its open tab; `<For>` gives every item its own
   * reactive scope, which is what makes that legitimate.
   */
  function Section(sectionProps: { chain: string[] }) {
    const [picked, setPicked] = createSignal<string | null>(null);
    // Until the user chooses, follow the content: opening on an empty `cols` — the ordinary state
    // before a source is loaded — would show "none defined" while another tab holds the only real
    // choice. After a click the choice sticks, rather than moving under them as options arrive.
    const open = () =>
      picked() ?? kindsOf().find((kind) => optionsOf(kind).length > 0) ?? kindsOf()[0] ?? "";

    return (
      <fieldset class="my-2 rounded-sm border border-border p-2">
        <legend class="px-1 text-xs font-semibold text-muted-foreground">
          {sectionProps.chain.length === 0
            ? "Direct"
            : `Through ${sectionProps.chain.join(" → ")}`}
        </legend>

        <Tabs
          group="kinds"
          items={kindsOf()}
          active={open()}
          onSelect={setPicked}
          count={(kind) => chosen(sectionProps.chain, kind).length}
        />

        <div role="tabpanel" data-kind={open()} class="max-h-40 overflow-y-auto p-2">
          {/*
            Checkboxes rather than a native `<select multiple>`: there, a plain click *replaces*
            the selection and keeping several requires Ctrl/Cmd-click, which is not discoverable
            and reads as "it will only take one". This also matches ListFilter, which already
            picks several of a known list this way.
          */}
          <Show
            when={optionsOf(open()).length > 0}
            fallback={<p class="text-xs italic text-muted-foreground">none defined</p>}
          >
            <div class="grid gap-x-3 sm:grid-cols-2 md:grid-cols-3">
              <For each={optionsOf(open())}>
                {(option) => (
                  <Checkbox
                    label={String(option)}
                    checked={chosen(sectionProps.chain, open()).includes(String(option))}
                    onChange={(checked) =>
                      toggle(sectionProps.chain, open(), String(option), checked)
                    }
                  />
                )}
              </For>
            </div>
          </Show>
        </div>
      </fieldset>
    );
  }


  return (
    <div class="my-2">
      <p class="text-xs font-semibold text-primary">{props.label}</p>

      <Show when={chips().length > 0}>
        <ul class="my-1 flex flex-wrap gap-1.5" aria-label={`${props.label} order`}>
          <For each={chips()}>
            {(chip, index) => (
              <li
                data-chip={chipLabel(chip)}
                draggable="true"
                class="inline-flex items-center gap-1.5 rounded-sm border border-border bg-muted px-2 py-0.5 text-xs"
                onDragStart={() => setDragging(index())}
                onDragOver={(event) => event.preventDefault()}
                onDrop={() => {
                  const from = dragging();
                  if (from !== null) reorder(from, index());
                  setDragging(null);
                }}
              >
                <span>{chipLabel(chip)}</span>
                {/* Native drag is not keyboard reachable, so the same move is a button. */}
                <button
                  type="button"
                  data-move="earlier"
                  aria-label={`move ${chipLabel(chip)} earlier`}
                  disabled={index() === 0}
                  onClick={() => reorder(index(), index() - 1)}
                >
                  ←
                </button>
                <button
                  type="button"
                  data-move="later"
                  aria-label={`move ${chipLabel(chip)} later`}
                  disabled={index() === chips().length - 1}
                  onClick={() => reorder(index(), index() + 1)}
                >
                  →
                </button>
              </li>
            )}
          </For>
        </ul>
      </Show>
      <For each={allChains()}>
        {(chain) => (
          <Section chain={chain} />
        )}
      </For>

      <Show when={chainOptions().length > 0}>
        {/*
          A chain is ORDERED — [a,b] names a different column from [b,a] — and neither a
          `<select multiple>` nor a checkbox grid preserves *click* order: both report DOM order.
          So the chain is built by appending on click and shown as it will be sent.
        */}
        <div class="mt-2" data-chain-builder>
          <p class="text-xs text-muted-foreground">
            add a pass-through
            <Show when={draft().length > 0}>
              <span class="ml-2 font-mono">{draft().join(" → ")}</span>
            </Show>
          </p>
          <div class="flex flex-wrap gap-1.5">
            <For each={chainOptions()}>
              {(option) => (
                <button
                  type="button"
                  class="rounded-sm border border-border px-2 py-0.5 text-xs"
                  onClick={() => setDraft([...draft(), option])}
                >
                  {option}
                </button>
              )}
            </For>
            <Show when={draft().length > 0}>
              <button
                type="button"
                data-chain="commit"
                class="rounded-sm border border-primary/30 bg-accent px-2 py-0.5 text-xs text-primary"
                onClick={() => {
                  addChain(draft());
                  setDraft([]);
                }}
              >
                add section
              </button>
              <button
                type="button"
                data-chain="clear"
                class="px-2 py-0.5 text-xs text-muted-foreground"
                onClick={() => setDraft([])}
              >
                clear
              </button>
            </Show>
          </div>
        </div>
      </Show>
    </div>
  );
}
