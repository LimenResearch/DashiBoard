// Mapping an IR node to the widget that renders it.
//
// Kept separate from the components deliberately: this is the part where correctness lives, it
// is pure, and it can be tested against the real vocabulary POST /get-card-ir serves. The
// components then only have to draw what they are told.
//
// The IR exists precisely so this mapping is a switch over a closed set rather than an attempt
// to recover intent from JSON Schema keywords (decisions section 13). A `tagged_object` says it
// is a variant selector; the equivalent schema says `allOf` of `if`/`then` over a `const`, from
// which the same fact has to be inferred.

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
  | {
      kind: "variant";
      options: string[];
      objects: { [option: string]: IRNode };
      default?: string;
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
  // A node the IR does not constrain. Reachable today: `ArrayIR{Any}()` serialises its items as
  // `{}`, which the glm and mixed_model formula IRs both do.
  | { kind: "unknown" };

/**
 * The same defs with one value removed from one vocabulary.
 *
 * Used to keep a thing from naming itself. A node listing its own id — as an input or as a step
 * in a `through` chain — is a cycle, and so is a group naming itself; the server rejects both, so
 * offering them is offering a choice that cannot come out well. Narrowing the vocabulary makes it
 * unrepresentable rather than merely invalid, which is the same move C2 makes for selector kind.
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
 * means the UI cannot drift from what the schema admits, and A7's one remaining validator leak
 * (that `oneOf` summarising when the *kind* is malformed) is retired by making the kind
 * unrepresentably wrong rather than merely invalid.
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
      };

    case "object": {
      const properties = (Array.isArray(n.properties) ? n.properties : []) as PropertyEntry[];
      // `properties: []` means two different things, and `additionalProperties` is the difference.
      // Closed, it is a thing that takes no settings — `pca`, `log`, `euclidean`; 18 branches say
      // this. Open, it is a field the IR does not describe at all: streamliner's `model` and
      // `training` accept arbitrary keys and *require* them, because Pipelines reads their widget
      // definitions from `.wdgs` files at runtime rather than from the type. Calling that an
      // object with no properties draws a form saying there is nothing to fill in, which is the
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
      if (w.default === undefined) return undefined;
      const branch = w.objects[w.default];
      const inner = branch === undefined ? undefined : defaultsFor(branch, defs);
      return { type: w.default, ...(inner !== undefined ? (inner as object) : {}) };
    }

    case "select":
    case "number":
    case "toggle":
    case "text":
    case "multiselect":
      return w.default;

    // A repeater's default is an empty list, which is what an absent key already means; and an
    // unknown node has nothing honest to offer.
    case "repeater":
    case "unknown":
      return undefined;
  }
}
