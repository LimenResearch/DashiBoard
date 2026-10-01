import type { SelectorRow } from "./selector";
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
 * The way `node` carries all of `names`, if it has one.
 *
 * A probe reply is parsed JSON, not a checked type, so a server that does not send `through` at
 * all leaves the field absent rather than empty. Read as "carries nothing": the picker then offers
 * no chain, which is wrong but quiet, where dereferencing it would take the page down.
 */
function optionFor(node: ProbeNode, names: readonly string[]): ThroughOption | undefined {
  return (node.through ?? []).find((t) => names.every((name) => t.cols.includes(name)));
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
  for (const id of row.chain) {
    if (names === null) return null;
    const node = nodes.find((n) => n.id === id);
    const option = node === undefined ? undefined : optionFor(node, names);
    // A chain the server would refuse tells us nothing about what comes next.
    if (option === undefined) return null;
    names = toOutputs(option, names);
  }
  return names;
}

/** `all`, narrowed to the nodes that can carry what `row` holds; `all` when that cannot be told. */
export function throughOptions(
  row: SelectorRow, all: string[], nodes: ProbeNode[], groups: Record<string, Selector[]>,
): string[] {
  // Redundant once the nodes are described — a node never carries its own output — but it is the
  // only rule left when they are not.
  const fresh = all.filter((id) => !row.chain.includes(id));
  if (nodes.length === 0) return fresh;
  const values = carried(row, nodes, groups);
  if (values === null) return fresh;
  return fresh.filter((id) => {
    const node = nodes.find((n) => n.id === id);
    return node !== undefined && optionFor(node, values) !== undefined;
  });
}
