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

/**
 * The properties a card declares where a preset can reach them: its own, and those of the branch
 * a variant property falls to when nothing is chosen — its default option, or its only one.
 * `within` names that variant property. So `order_by` inside a streamliner's funnel is the same
 * shared field as `order_by` on a split.
 */
function declared(card: IRNode | undefined, defs: Defs): (Property & { within?: string })[] {
  const out: (Property & { within?: string })[] = [];
  for (const property of ((card?.properties ?? []) as Property[])) {
    out.push(property);
    const widget = widgetFor(property.value, defs);
    if (widget.kind !== "variant") continue;
    const option = widget.default ?? (widget.options.length === 1 ? widget.options[0] : undefined);
    const branch = option === undefined ? undefined : widget.objects[option];
    for (const inner of ((branch?.properties ?? []) as Property[])) out.push({ ...inner, within: property.key });
  }
  return out;
}

/**
 * The presets a card of this type has a field for, ready to be merged into a new card: each at
 * the place the card declares the field, which may be inside a variant property.
 */
export function presetsFor(
  fields: readonly PresetField[], card: IRNode | undefined, presets: PresetStore, defs: Defs = {},
): { [key: string]: unknown } {
  const offered = new Set(fields.map((field) => field.key));
  const out: { [key: string]: unknown } = {};
  for (const property of declared(card, defs)) {
    if (!offered.has(property.key)) continue;
    const value = presets[property.key];
    // An empty list is emptiness, not a choice, and nothing to start a card from.
    const set = Array.isArray(value) ? value.length > 0 : value !== undefined;
    if (!set) continue;
    if (property.within === undefined) out[property.key] = structuredClone(value);
    else out[property.within] = { ...(out[property.within] as object | undefined), [property.key]: structuredClone(value) };
  }
  return out;
}

/**
 * A new card's defaults with its presets laid over them. A preset for a field replaces the
 * field's default whole; one that sits inside a variant property is added to that property's
 * own defaults, which it would otherwise wipe out.
 */
export function mergePresets(
  defaults: { [key: string]: unknown }, preset: { [key: string]: unknown }, fields: readonly PresetField[],
): { [key: string]: unknown } {
  const own = new Set(fields.map((field) => field.key));
  const out = { ...defaults };
  for (const [key, value] of Object.entries(preset)) {
    out[key] = own.has(key) ? value : { ...(defaults[key] as object | undefined), ...(value as object) };
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
    // Once per card type, wherever the card declares it.
    const counted = new Set<string>();
    for (const property of declared(card, defs)) {
      if (CORE.has(property.key) || counted.has(property.key)) continue;
      counted.add(property.key);
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
