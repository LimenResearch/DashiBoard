// Mapping an IR node to the widget that renders it.
//
// Kept separate from the components deliberately: this is the part where correctness lives, it
// is pure, and it can be tested against the real vocabulary POST /get-card-ir serves. The
// components then only have to draw what they are told.
//
// The IR exists precisely so this mapping is a switch over a closed set rather than an attempt to
// recover intent from JSON Schema keywords. A `tagged_object` says it is a variant selector; the
// equivalent schema says `allOf` of `if`/`then` over a `const`, from which it has to be inferred.

export type IRNode = { [key: string]: unknown };
export type Defs = { [name: string]: IRNode };

/** One entry of an `object` node's ordered `properties` array. */
export type PropertyEntry = { key: string; required: boolean; value: IRNode };

export type Widget =
  | { kind: "text"; minLength?: number; default?: string }
  | { kind: "select"; options: (string | number)[]; default?: string | number }
  | {
      kind: "number";
      integer: boolean;
      min?: number;
      max?: number;
      exclusiveMin?: number;
      exclusiveMax?: number;
      default?: number;
    }
  | { kind: "toggle"; default?: boolean }
  | {
      kind: "multiselect";
      options: (string | number)[];
      minItems?: number;
      default?: unknown[];
    }
  | { kind: "repeater"; items: IRNode; minItems?: number }
  /**
   * Plain values in order, repeats meant — typed comma-separated. `options` are the values allowed
   * when they come from a fixed set.
   */
  | {
      kind: "list";
      item: "string" | "number" | "integer";
      options?: (string | number)[];
      minItems?: number;
      default?: unknown[];
    }
  | {
      kind: "variant";
      options: string[];
      objects: { [option: string]: IRNode };
      default?: string;
      /** Where the options come from when they are files — `model`, `training` — so a form can show them. */
      optionsFrom?: string;
    }
  | { kind: "object"; title?: string; properties: PropertyEntry[] }
  /**
   * A variable selector: exactly one of several *kinds*, each choosing from its own vocabulary,
   * plus an optional ordered `through` chain. Recognised structurally — from the `oneOf` the IR
   * carries in `constraints` — rather than by hard-coding key names, so "exactly one kind" is
   * data rather than a convention this file agreed to.
   */
  | {
      kind: "selector";
      kinds: string[];
      options: { [kind: string]: (string | number)[] };
      through: IRNode;
    }
  /**
   * Names to values of one kind — a transform per column, say. The names are not the schema's to
   * list: `keysFrom` says which sibling field they come from.
   */
  | { kind: "map"; values: (string | number)[]; keysFrom?: string }
  // A node the IR does not constrain. Reachable today: `ArrayIR{Any}()` serialises its items as
  // `{}`, which the glm and mixed_model formula IRs both do.
  | { kind: "unknown" };

/**
 * The same defs with one value removed from one vocabulary.
 *
 * Used to keep a thing from naming itself. A node listing its own id — as an input or as a step
 * in a `through` chain — is a cycle, and so is a group naming itself; the server rejects both, so
 * offering them is offering a choice that cannot come out well. Narrowing the vocabulary makes it
 * unrepresentable rather than merely invalid.
 *
 * Only *self*-reference is removed here. Excluding everything downstream would mean rebuilding
 * the dependency graph in the browser, which is the server's job and already done: a longer cycle
 * comes back from the probe.
 */
export function withoutOption(defs: Defs, key: string, value: string): Defs {
  const vocabulary = defs[key];
  if (vocabulary === undefined || !Array.isArray(vocabulary.enum)) return defs;
  return { ...defs, [key]: { ...vocabulary, enum: vocabulary.enum.filter((o) => o !== value) } };
}

/** `defs` with one vocabulary cut down to the names in `allowed`, in its own order. */
export function onlyOptions(defs: Defs, key: string, allowed: readonly string[]): Defs {
  const vocabulary = defs[key];
  if (vocabulary === undefined || !Array.isArray(vocabulary.enum)) return defs;
  const keep = new Set<unknown>(allowed);
  return { ...defs, [key]: { ...vocabulary, enum: vocabulary.enum.filter((o) => keep.has(o)) } };
}

const REF_PREFIX = "#/$defs/";

/** Follow `$ref` chains into `$defs`. An unresolvable or cyclic ref yields `{}`, not a throw. */
export function resolveRef(node: IRNode, defs: Defs): IRNode {
  let current = node;
  const seen = new Set<string>();
  while (typeof current.$ref === "string") {
    const ref = current.$ref;
    if (seen.has(ref) || !ref.startsWith(REF_PREFIX)) return {};
    seen.add(ref);
    const target = defs[ref.slice(REF_PREFIX.length)];
    if (target === undefined) return {};
    current = target;
  }
  return current;
}

/**
 * The kinds a selector offers, or `null` if this object is not one.
 *
 * Read off the `oneOf` the IR carries in `constraints` — `[{required: ["nodes"]}, …]` — which is
 * the gate the server enforces. Taking the kinds from there rather than from a literal list here
 * means the UI cannot drift from what the schema admits, and a malformed kind becomes
 * unrepresentable rather than something the server has to refuse.
 */
function selectorKinds(node: IRNode): string[] | null {
  const constraints = Array.isArray(node.constraints) ? node.constraints : [];
  for (const constraint of constraints) {
    const branches = (constraint as { oneOf?: unknown }).oneOf;
    if (!Array.isArray(branches)) continue;
    const kinds = branches.map((branch) => {
      const required = (branch as { required?: unknown }).required;
      return Array.isArray(required) && required.length === 1 ? String(required[0]) : null;
    });
    if (kinds.length > 0 && kinds.every((kind) => kind !== null)) return kinds as string[];
  }
  return null;
}

const num = (x: unknown) => (typeof x === "number" ? x : undefined);

export function widgetFor(node: IRNode, defs: Defs): Widget {
  const n = resolveRef(node, defs);

  switch (n.type) {
    case "string":
      return Array.isArray(n.enum)
        ? { kind: "select", options: n.enum, default: n.default as string | undefined }
        : {
            kind: "text",
            minLength: num(n.minLength),
            default: n.default as string | undefined,
          };

    case "integer":
    case "number":
      // An enum is a choice regardless of the values' type, so it is a select rather than a
      // number field with a validation rule the user has to discover by being wrong.
      return Array.isArray(n.enum)
        ? { kind: "select", options: n.enum, default: n.default as number | undefined }
        : {
            kind: "number",
            integer: n.type === "integer",
            min: num(n.minimum),
            max: num(n.maximum),
            exclusiveMin: num(n.exclusiveMinimum),
            exclusiveMax: num(n.exclusiveMaximum),
            default: num(n.default),
          };

    case "boolean":
      return { kind: "toggle", default: n.default as boolean | undefined };

    case "array": {
      const raw = (n.items ?? {}) as IRNode;
      const items = resolveRef(raw, defs);
      // Plain values written in place: a set (`uniqueItems`) is on/off choices; otherwise the
      // values are typed in order, repeats meant, with the allowed ones offered when they come
      // from a fixed set. Items given by a reference name things from a vocabulary — columns,
      // nodes — and stay a choice of names below.
      const scalar = items.type === "string" || items.type === "number" || items.type === "integer";
      if (scalar && typeof raw.$ref !== "string") {
        const options = Array.isArray(items.enum) ? (items.enum as (string | number)[]) : undefined;
        if (n.uniqueItems === true)
          return {
            kind: "multiselect",
            options: options ?? [],
            minItems: num(n.minItems),
            default: Array.isArray(n.default) ? n.default : undefined,
          };
        const list: Extract<Widget, { kind: "list" }> = {
          kind: "list", item: items.type as "string" | "number" | "integer", minItems: num(n.minItems),
        };
        if (options !== undefined) list.options = options;
        if (Array.isArray(n.default)) list.default = n.default;
        return list;
      }
      // An array over an enum is the multi-select case — including a `$defs/variables`
      // reference, whose items resolve to the source table's column enum.
      return Array.isArray(items.enum)
        ? {
            kind: "multiselect",
            options: items.enum,
            minItems: num(n.minItems),
            default: Array.isArray(n.default) ? n.default : undefined,
          }
        : { kind: "repeater", items: raw, minItems: num(n.minItems) };
    }

    case "tagged_object":
      return {
        kind: "variant",
        options: (Array.isArray(n.options) ? n.options : []) as string[],
        objects: (n.objects ?? {}) as { [option: string]: IRNode },
        default: n.default_option as string | undefined,
        ...(typeof n.options_from === "string" ? { optionsFrom: n.options_from } : {}),
      };

    case "object": {
      const properties = (Array.isArray(n.properties) ? n.properties : []) as PropertyEntry[];
      // `properties: []` means two different things, and `additionalProperties` is the difference.
      // Closed, it is a thing that takes no settings — `pca`, `log`, `euclidean`; 18 branches say
      // this. Open, it is a field the IR does not describe at all: streamliner's `funnel` branch,
      // built by `EmptyTaggedObjectIR(...; additionalProperties = true)` under a standing
      // "make schema more specific" TODO in `Pipelines/src/cards/streamliner.jl`. Calling that an
      // object with no settings draws a form saying there is nothing to fill in, which is the
      // opposite of true — so it is reported as undescribed, the same as `ArrayIR{Any}`.
      if (properties.length === 0 && n.additionalProperties === true) return { kind: "unknown" };
      const kinds = selectorKinds(n);
      if (kinds !== null) {
        const entry = (key: string) => properties.find((p) => p.key === key)?.value ?? {};
        const options: { [kind: string]: (string | number)[] } = {};
        for (const kind of kinds) {
          const widget = widgetFor(entry(kind), defs);
          options[kind] = widget.kind === "multiselect" || widget.kind === "select"
            ? widget.options
            : [];
        }
        return { kind: "selector", kinds, options, through: entry("through") };
      }
      return {
        kind: "object",
        title: n.title as string | undefined,
        properties,
      };
    }

    case "map": {
      const values = resolveRef((n.values ?? {}) as IRNode, defs);
      return {
        kind: "map",
        values: Array.isArray(values.enum) ? values.enum : [],
        ...(typeof n.keys_from === "string" ? { keysFrom: n.keys_from } : {}),
      };
    }

    // `nodes: str | list[str]` — one value or several, over one vocabulary. A multiselect covers
    // both, since a single selection is a one-element list.
    case "one_or_many": {
      const array = (n.array ?? {}) as IRNode;
      const items = resolveRef((array.items ?? {}) as IRNode, defs);
      return {
        kind: "multiselect",
        options: Array.isArray(items.enum) ? items.enum : [],
        minItems: num(array.minItems),
      };
    }

    default:
      return { kind: "unknown" };
  }
}

/**
 * The options a sibling's choice allows for the property `key`, read from the object's `if`/`then`
 * constraints: "if `model.type` is this, `select`'s items are these".
 *
 * `undefined` when no rule mentions `key` — the property is an ordinary one. `null` when rules
 * exist and none applies, which is a sibling not chosen yet. Nothing here knows which card or
 * which fields: it is the general case of one field's options depending on another's value.
 */
export function conditionalOptions(
  node: IRNode, key: string, value: Record<string, unknown>,
): string[] | null | undefined {
  const constraints = (Array.isArray(node.constraints) ? node.constraints : []) as Record<string, any>[];
  const rules = constraints.filter((c) => Array.isArray(c?.then?.properties?.[key]?.items?.enum));
  if (rules.length === 0) return undefined;
  for (const rule of rules) {
    const conditions = Object.entries((rule.if?.properties ?? {}) as Record<string, any>);
    const holds = conditions.every(([sibling, schema]) =>
      (value[sibling] as Record<string, unknown> | undefined)?.type === schema?.properties?.type?.const);
    if (holds) return (rule.then.properties[key].items.enum as unknown[]).map(String);
  }
  return null;
}

/** Whether a field drawn as `widget` would take `value` as it is. */
function accepts(widget: Widget, value: unknown): boolean {
  const record = (v: unknown) => !!v && typeof v === "object" && !Array.isArray(v);
  switch (widget.kind) {
    case "text": return typeof value === "string";
    case "select": return widget.options.includes(value as string | number);
    case "number": return typeof value === "number";
    case "toggle": return typeof value === "boolean";
    case "multiselect": return Array.isArray(value) && value.every((v) => widget.options.includes(v as string | number));
    case "repeater":
    case "list": return Array.isArray(value);
    case "selector": return Array.isArray(value) || record(value);
    case "variant":
    case "object":
    case "map": return record(value);
    case "unknown": return true;
  }
}

/**
 * The value a variant takes when `branch` is chosen in place of what held `previous`: the branch's
 * defaults, with every field the branch also declares kept as it was — the columns and the order
 * of a funnel survive a change of funnel type. A kept value the branch would refuse gives way to
 * the branch's default; a field the branch lacks is dropped.
 */
export function carryShared(previous: unknown, branch: IRNode, defs: Defs): Record<string, unknown> {
  const base = { ...((defaultsFor(branch, defs) ?? {}) as Record<string, unknown>) };
  const held = (previous && typeof previous === "object" && !Array.isArray(previous) ? previous : {}) as Record<string, unknown>;
  for (const property of (resolveRef(branch, defs).properties ?? []) as PropertyEntry[]) {
    if (!(property.key in held) || property.key === "type") continue;
    const widget = widgetFor(property.value, defs);
    const value = held[property.key];
    const record = !!value && typeof value === "object" && !Array.isArray(value);
    // A nested choice is kept only if the new branch offers it, and then trimmed to that option's
    // own fields; a nested object is trimmed to the new shape.
    if (widget.kind === "variant") {
      const named = (value as Record<string, unknown> | undefined)?.type;
      const option = typeof named === "string" ? named : widget.default ?? "";
      if (!record || !widget.options.includes(option)) continue;
      const inner = carryShared(value, widget.objects[option], defs);
      base[property.key] = typeof named === "string" ? { ...inner, type: named } : inner;
      continue;
    }
    if (widget.kind === "object") {
      if (record) base[property.key] = carryShared(value, property.value, defs);
      continue;
    }
    if (accepts(widget, value)) base[property.key] = value;
  }
  return base;
}

/**
 * The value an IR node implies when nothing has been entered.
 *
 * A card added to the document used to carry only its `type`, while the form displayed every
 * default the IR declares — so the screen said `suffix: rescaled` and the document said nothing,
 * and downloading the cards produced a file that did not match what had been on screen. The
 * server fills the same defaults on its way in, so the *behaviour* was consistent; what differed
 * was the artefact the author was editing, which is the one they keep.
 *
 * Two things it deliberately does not do.
 *
 * It supplies nothing for a field that has no default. A required field without one is the
 * author's to fill, and writing a value there would make an unanswered question look answered —
 * which is exactly what a confirmation step exists to catch.
 *
 * And it leaves a variant unset unless the IR names a `default_option`. `options` arrives from a
 * Julia `Dict`, so its order carries no intent: taking the first would assert a choice nobody
 * made, and potentially a different one between two runs of the server.
 */
export function defaultsFor(node: IRNode, defs: Defs): unknown {
  const w = widgetFor(node, defs);
  switch (w.kind) {
    case "object": {
      const out: Record<string, unknown> = {};
      for (const entry of w.properties) {
        const value = defaultsFor(entry.value, defs);
        if (value !== undefined) out[entry.key] = value;
      }
      return Object.keys(out).length > 0 ? out : undefined;
    }

    case "variant": {
      // A lone option is taken without asking, as the form draws it.
      const option = w.default ?? (w.options.length === 1 ? w.options[0] : undefined);
      if (option === undefined) return undefined;
      const branch = w.objects[option];
      const inner = branch === undefined ? undefined : defaultsFor(branch, defs);
      // The blank option is the one meant when none is named, so it is not named: what is left
      // is the branch's own defaults, or nothing.
      if (option === "") return inner;
      return { type: option, ...(inner !== undefined ? (inner as object) : {}) };
    }

    case "select":
    case "number":
    case "toggle":
    case "text":
    case "multiselect":
    case "list":
      return w.default;

    // A repeater's default is an empty list and a map's an empty map, which is what an absent
    // key already means; and an unknown node has nothing honest to offer.
    case "map":
    case "repeater":
    case "unknown":
      return undefined;
  }
}

/**
 * The values typed into a list's box: separated by commas, spaces ignored, numbers read as
 * numbers. The first value that cannot be read is named, and then nothing is returned; a text
 * ending in a comma is still being typed.
 */
export function parseList(
  text: string, item: "string" | "number" | "integer", options?: (string | number)[],
): { values: (string | number)[] } | { error: string } | { incomplete: true } {
  if (text.trim() === "") return { values: [] };
  const values: (string | number)[] = [];
  const tokens = text.split(",");
  for (const [at, raw] of tokens.entries()) {
    const token = raw.trim();
    // A comma just typed is the next value on its way.
    if (token === "" && at === tokens.length - 1) return { incomplete: true };
    if (token === "") return { error: "a value is missing between two commas" };
    let value: string | number = token;
    if (item !== "string") {
      const parsed = Number(token);
      if (Number.isNaN(parsed)) return { error: `${token} is not a number` };
      if (item === "integer" && !Number.isInteger(parsed)) return { error: `${token} is not a whole number` };
      value = parsed;
    }
    if (options !== undefined && !options.some((o) => String(o) === String(value)))
      return { error: `${token} is not one of ${options.join(", ")}` };
    values.push(value);
  }
  return { values };
}

/** A list as its box shows it. */
export const listText = (values: unknown): string => (Array.isArray(values) ? values.map(String).join(", ") : "");
