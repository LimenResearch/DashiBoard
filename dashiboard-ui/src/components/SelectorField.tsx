import { For, Show } from "solid-js";
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

  const kindsOf = () => {
    const w = widget();
    return w.kind === "selector" ? w.kinds : [];
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
    for (const existing of chains(items())) {
      const existingKey = JSON.stringify(existing);
      for (const k of kindsOf()) {
        const vals = existingKey === key && k === kind ? values : chosen(existing, k);
        if (vals.length === 0) continue;
        next.push(existing.length === 0 ? { [k]: vals } : { [k]: vals, through: existing });
      }
    }
    props.onChange(next);
  }

  function addChain(chain: string[]) {
    if (chain.length === 0) return;
    // A chain with no values yet has nothing to store, so it is held by the control itself
    // until something is chosen. Writing `{through: [...]}` alone would fail the `oneOf` gate.
    props.onChange([...items(), { cols: [], through: chain } as SelectorItem]);
  }

  return (
    <div class="my-2">
      <p class="text-sm font-semibold text-blue-800">{props.label}</p>
      <For each={chains(items())}>
        {(chain) => (
          <fieldset class="my-2 border-l-2 border-gray-200 pl-3">
            <legend class="text-xs text-gray-500">
              {chain.length === 0 ? "Direct" : `Through ${chain.join(" → ")}`}
            </legend>
            <For each={kindsOf()}>
              {(kind) => (
                <div class="my-1">
                  <label class="block text-xs text-gray-600">{kind}</label>
                  <select
                    multiple
                    size={Math.min(Math.max(optionsOf(kind).length, 2), 6)}
                    class="w-full rounded border border-gray-200"
                    onChange={(event) =>
                      write(
                        chain,
                        kind,
                        [...event.currentTarget.selectedOptions].map((o) => o.value),
                      )
                    }
                  >
                    <For each={optionsOf(kind)}>
                      {(option) => (
                        <option
                          value={String(option)}
                          selected={chosen(chain, kind).includes(String(option))}
                        >
                          {option}
                        </option>
                      )}
                    </For>
                  </select>
                </div>
              )}
            </For>
          </fieldset>
        )}
      </For>

      <Show when={chainOptions().length > 0}>
        <label class="block text-xs text-gray-600">add a pass-through</label>
        <select
          multiple
          size={Math.min(Math.max(chainOptions().length, 2), 4)}
          class="w-full rounded border border-gray-200"
          onChange={(event) =>
            addChain([...event.currentTarget.selectedOptions].map((o) => o.value))
          }
        >
          <For each={chainOptions()}>
            {(option) => <option value={option}>{option}</option>}
          </For>
        </select>
      </Show>
    </div>
  );
}
