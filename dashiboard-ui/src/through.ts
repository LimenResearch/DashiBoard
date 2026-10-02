import { parseStep, type SelectorRow } from "./selector";
import type { ProbeNode, Selector, ThroughOption } from "./stores";

// Which nodes a `through` chain can pass through next, from what the server said each node can
// carry. A node that does not derive its outputs from the value cannot transform it, and the
// pipeline refuses such a chain — so offering it would be offering a refusal.

/**
 * What `names` become after passing through `t`.
 *
 * A port of `Pipelines.to_outputs`; see `ThroughOption` for why the rule is carried here at all.
 * The index varies slowest because the server broadcasts names against `1:number` and flattens
 * the result column-major.
 */
export function toOutputs(t: ThroughOption, names: readonly string[]): string[] {
  const renamed = t.suffix == null ? [...names] : names.map((name) => `${name}_${t.suffix}`);
  if (t.number == null) return renamed;
  const out: string[] = [];
  for (let i = 1; i <= t.number; i++) for (const name of renamed) out.push(`${name}_${i}`);
  return out;
}

/**
 * The products of `node` that can carry all of `names` — the ones a bare step would take.
 *
 * A probe reply is parsed JSON, not a checked type, so a server that does not send `through` at
 * all leaves the field absent rather than empty. Read as "carries nothing": the picker then offers
 * no chain, which is wrong but quiet, where dereferencing it would take the page down.
 */
function carriers(node: ProbeNode, names: readonly string[]): ThroughOption[] {
  return (node.through ?? []).filter((t) => names.every((name) => t.cols.includes(name)));
}

/** The products a step takes: every carrier for a bare one, exactly those named otherwise. */
function chosen(node: ProbeNode, names: readonly string[], groups: readonly string[]): ThroughOption[] | null {
  const able = carriers(node, names);
  if (groups.length === 0) return able.length === 0 ? null : able;
  const named = groups.map((group) => able.find((t) => t.group === group));
  return named.every((t) => t !== undefined) ? (named as ThroughOption[]) : null;
}

/** The columns the value itself contributes, before any chain. `null` when unknown here. */
function initial(row: SelectorRow, nodes: ProbeNode[], groups: Record<string, Selector[]>): string[] | null {
  switch (row.kind) {
    case "cols": return [row.value];
    case "nodes": return nodes.find((node) => node.id === row.value)?.outputs ?? null;
    case "groups": {
      const items = groups[row.value];
      // Only plain column items are known by name here; anything else is the server's to resolve.
      if (items === undefined || items.some((item) => !("cols" in item) || item.through !== undefined)) return null;
      return items.flatMap((item) => (Array.isArray(item.cols) ? item.cols : [item.cols as string]));
    }
    default: return null;
  }
}

/** What the row hands to its next step, walking the chain it already has. */
function carried(row: SelectorRow, nodes: ProbeNode[], groups: Record<string, Selector[]>): string[] | null {
  let names = initial(row, nodes, groups);
  for (const token of row.chain) {
    if (names === null) return null;
    const step = parseStep(token);
    const node = nodes.find((n) => n.id === step.node);
    const products = node === undefined ? null : chosen(node, names, step.groups);
    // A chain the server would refuse tells us nothing about what comes next.
    if (products === null) return null;
    const handed = names;
    // Each product is applied to everything carried, in turn — the server's order.
    names = products.flatMap((product) => toOutputs(product, handed));
  }
  return names;
}

/** `all`, narrowed to the nodes that can carry what `row` holds; `all` when that cannot be told. */
export function throughOptions(
  row: SelectorRow, all: string[], nodes: ProbeNode[], groups: Record<string, Selector[]>,
): string[] {
  // Two things hold whatever the server has said, so they are filtered here rather than left to
  // the column check below: a chain never revisits a node, and a node never carries what it wrote
  // itself. Both are redundant once the nodes are described — and they are all that is left when
  // the document does not build, so nothing has been described at all.
  const visited = new Set(row.chain.map((token) => parseStep(token).node));
  const fresh = all.filter((id) => !visited.has(id) && !(row.kind === "nodes" && id === row.value));
  if (nodes.length === 0) return fresh;
  const values = carried(row, nodes, groups);
  if (values === null) return fresh;
  return fresh.filter((id) => {
    const node = nodes.find((n) => n.id === id);
    return node !== undefined && carriers(node, values).length > 0;
  });
}

/**
 * The products the step `token` could still be narrowed to — the named carriers it does not
 * already list. `row` is the selection *before* that step. Empty for a node with one product, or
 * one whose products have no names.
 */
export function groupsFor(
  token: string, row: SelectorRow, nodes: ProbeNode[], groups: Record<string, Selector[]>,
): string[] {
  const step = parseStep(token);
  const node = nodes.find((n) => n.id === step.node);
  const values = carried(row, nodes, groups);
  if (node === undefined || values === null) return [];
  return carriers(node, values)
    .map((t) => t.group)
    .filter((group): group is string => group !== null && !step.groups.includes(group));
}
