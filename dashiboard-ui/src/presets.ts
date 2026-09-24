import { widgetFor, type Defs, type IRNode } from "./ir";
import type { SelectorItem } from "./selector";

// Starting values for the fields cards share — set once, copied into each card made afterwards.
//
// Which fields those are is read from the IR rather than listed here, so a card type added to
// Pipelines brings its shared fields with it. What a card *operates on* is left out by name: a
// pipeline-wide `inputs` would be naming the pipeline's one job, which is not what a card is.

/** A field's value, in the shape the card's own field holds. */
export type PresetStore = { [field: string]: SelectorItem | SelectorItem[] };

export type PresetField = {
  key: string;
  /** One value rather than a list — `$defs/variable`, which `SelectorField` draws with `single`. */
  single: boolean;
  /** The item node, ready for `SelectorField`: the field itself, or a list's item. */
  node: IRNode;
};

type Property = { key: string; value: IRNode };

/** The presets a card of this type has a field for, ready to be merged into a new card. */
export function presetsFor(
  fields: readonly PresetField[], card: IRNode | undefined, presets: PresetStore,
): PresetStore {
  const has = new Set(((card?.properties ?? []) as Property[]).map((property) => property.key));
  const out: PresetStore = {};
  for (const field of fields) {
    const value = presets[field.key];
    // An empty list is emptiness, not a choice, and nothing to start a card from.
    const set = Array.isArray(value) ? value.length > 0 : value !== undefined;
    if (set && has.has(field.key)) out[field.key] = structuredClone(value);
  }
  return out;
}

const CORE = new Set(["inputs", "targets", "input"]);
/** A preset is for what cards share; a selector field only one type has is that card's business. */
const SHARED_BY = 2;


/** The field as a selector, if it is one: one value, or a list of them. */
function asSelector(value: IRNode, defs: Defs): Pick<PresetField, "single" | "node"> | null {
  const widget = widgetFor(value, defs);
  if (widget.kind === "selector") return { single: true, node: value };
  if (widget.kind !== "repeater") return null;
  return widgetFor(widget.items, defs).kind === "selector"
    ? { single: false, node: widget.items }
    : null;
}

/** The fields a preset may be set for, most widely shared first, then by name. */
export function presetFields(cards: { [type: string]: IRNode }, defs: Defs): PresetField[] {
  const found = new Map<string, { field: PresetField; types: number }>();
  for (const card of Object.values(cards)) {
    for (const property of (card.properties ?? []) as Property[]) {
      if (CORE.has(property.key)) continue;
      const seen = found.get(property.key);
      if (seen !== undefined) {
        seen.types += 1;
        continue;
      }
      const selector = asSelector(property.value, defs);
      if (selector !== null) found.set(property.key, { field: { key: property.key, ...selector }, types: 1 });
    }
  }
  return [...found.values()]
    .filter((entry) => entry.types >= SHARED_BY)
    .sort((a, b) => b.types - a.types || a.field.key.localeCompare(b.field.key))
    .map((entry) => entry.field);
}
