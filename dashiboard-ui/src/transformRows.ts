// Which columns a transform map has a row for.
//
// The server resolves a list — its groups, its nodes, its chains — and says what it came to; the
// form does not repeat that. What it adds is what the author wrote plainly, since a column typed
// a moment ago is not in the last answer yet, and what it does alone is tidy up after a plain
// column that was taken out.

type Item = { cols?: unknown; through?: unknown };

/** The columns a list names outright: its `cols` entries that pass through nothing, in order. */
export function plainColumns(items: unknown): string[] {
  if (!Array.isArray(items)) return [];
  return (items as Item[]).flatMap((item) => {
    if (item === null || typeof item !== "object" || item.cols === undefined) return [];
    if (Array.isArray(item.through) && item.through.length > 0) return [];
    return (Array.isArray(item.cols) ? item.cols : [item.cols]).map(String);
  });
}

/**
 * The rows to draw: `live` for the columns of the list, `stale` for entries naming a column the
 * list does not reach.
 *
 * `resolved` is what the server said the list came to, and `null` when it has not said — before
 * an answer, and while the document does not build. Then an entry cannot be judged, but it is in
 * the document, so it gets a live row all the same and can be put back to identity. `refused`
 * are the entries the server turned down by name: a document refused for one is not described at
 * all, so the refusal is the only thing that says which entry is stale.
 */
export function transformRows(
  resolved: readonly string[] | null, plain: readonly string[], held: Record<string, string>,
  refused: readonly string[] = [],
): { live: string[]; stale: string[] } {
  const live: string[] = [];
  const add = (column: string) => {
    if (!live.includes(column) && !refused.includes(column)) live.push(column);
  };
  (resolved ?? []).forEach(add);
  plain.forEach(add);
  if (resolved === null) Object.keys(held).forEach(add);
  const stale = Object.keys(held).filter((column) => !live.includes(column));
  return { live, stale };
}

/**
 * The entries of card `nodeIndex`'s map `field` that the server refused, read off the pointers of
 * its issues: `/nodes/2/card/funnel/input_transforms/TEMP_z`.
 */
export function refusedKeys(
  issues: readonly { pointer: string; reason: string }[], nodeIndex: number, field: string,
): string[] {
  const unescape = (token: string) => token.replace(/~1/g, "/").replace(/~0/g, "~");
  return issues.flatMap((issue) => {
    if (issue.reason !== "transforms") return [];
    const tokens = issue.pointer.split("/").slice(1);
    if (tokens[0] !== "nodes" || tokens[1] !== String(nodeIndex) || tokens.length < 5) return [];
    return tokens[tokens.length - 2] === field ? [unescape(tokens[tokens.length - 1])] : [];
  });
}

/**
 * `held` without the entries of the plain columns that left the list, or `undefined` when none
 * is left. A column reached some other way — through a group, a chain — is the server's to judge.
 */
export function pruneMap(
  held: Record<string, string> | undefined, before: readonly string[], after: readonly string[],
): Record<string, string> | undefined {
  if (held === undefined) return undefined;
  const gone = before.filter((column) => !after.includes(column));
  const kept = Object.fromEntries(Object.entries(held).filter(([column]) => !gone.includes(column)));
  return Object.keys(kept).length > 0 ? kept : undefined;
}
