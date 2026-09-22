import type { SelectorRow } from "./selector";
import type { ProbeNode, Selector } from "./stores";

// Which nodes a `through` chain can pass through next, from what the server said each node reads
// and writes. A node that never reads the value cannot transform it, so offering it is offering a
// choice the server refuses. Names are the server's; nothing is concatenated here.

/** What the row hands to its next step: the value's columns, or the last step's outputs. */
function carried(row: SelectorRow, nodes: ProbeNode[], groups: Record<string, Selector[]>): string[] | null {
  const last = row.chain.at(-1);
  if (last !== undefined) return nodes.find((node) => node.id === last)?.outputs ?? null;
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

/** `all`, narrowed to the nodes that read what `row` carries; `all` when that cannot be told. */
export function throughOptions(
  row: SelectorRow, all: string[], nodes: ProbeNode[], groups: Record<string, Selector[]>,
): string[] {
  // A chain never revisits a node: it would have to read its own output.
  const fresh = all.filter((id) => !row.chain.includes(id));
  if (nodes.length === 0) return fresh;
  const values = carried(row, nodes, groups);
  if (values === null) return fresh;
  const reads = new Set(nodes.filter((node) => node.inputs.some((input) => values.includes(input))).map((node) => node.id));
  return fresh.filter((id) => reads.has(id));
}
