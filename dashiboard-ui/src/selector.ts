// The variable field's document model, kept apart from the control that edits it.
//
// A field is an *ordered list of items*, each naming exactly one of `cols`/`nodes`/`groups` — the
// `oneOf` gate — with an optional ordered `through` chain. The picker finds that shape awkward to
// edit, because a single item can hold several values; it works in flat **rows** instead, one per
// value, and converts at the boundary.
//
// That conversion is lossless in one direction only, and the asymmetry is the whole design:
// `[{cols: ["PRES","TEMP"]}]` and two single-value items resolve identically (case A ≡ B), so
// splitting is free — but two items whose `through` differs are *not* interchangeable, and the
// same value may legitimately appear twice under different qualifications (case E). So rows carry
// the chain, and only consecutive runs sharing a kind and a chain are merged back together.
//
// There is deliberately no resolver here. `through` names a column by concatenating node suffixes,
// and that rule belongs to DashiBoard: a copy of it in TypeScript is a second source of truth for
// a naming law, which is what A10 exists to delete and what C2's second constraint was withdrawn
// for (06-design.md, amended 2026-09-12). The UI writes the TOML; DashiBoard resolves it.

export type SelectorItem = {
  through?: string[];
  [kind: string]: unknown;
};

/** One value with its qualification — what the control actually manipulates. */
export type SelectorRow = {
  kind: string;
  value: string;
  chain: string[];
};

export const asItems = (value: unknown): SelectorItem[] =>
  Array.isArray(value) ? (value as SelectorItem[]) : [];

/** A selector is one-or-many: `"PRES"` and `["PRES"]` mean the same thing. */
const asList = (value: unknown): string[] =>
  value === undefined || value === null
    ? []
    : Array.isArray(value)
      ? value.map(String)
      : [String(value)];

/** Chains are compared by identity *and order* — `[a,b]` names a different column from `[b,a]`. */
export const chainKey = (chain: string[]) => JSON.stringify(chain);

/** Items to rows: one row per value, each carrying the item's chain. */
export function expand(items: SelectorItem[], kinds: readonly string[]): SelectorRow[] {
  return items.flatMap((item) => {
    const chain = Array.isArray(item.through) ? item.through.map(String) : [];
    return kinds.flatMap((kind) =>
      asList(item[kind]).map((value) => ({ kind, value, chain })),
    );
  });
}

/**
 * Rows back to items, merging only *consecutive* runs of the same kind and chain.
 *
 * Consecutive matters. Merging two `cols` runs separated by a `groups` item would move those
 * columns next to each other, and the field is ordered — §12's positional `weights` rule reads
 * that order, so a silent reordering changes which weight lands on which column.
 */
export function collapse(rows: SelectorRow[]): SelectorItem[] {
  const runs: { kind: string; chain: string[]; values: string[] }[] = [];
  for (const row of rows) {
    const last = runs[runs.length - 1];
    if (last && last.kind === row.kind && chainKey(last.chain) === chainKey(row.chain)) {
      last.values.push(row.value);
    } else {
      runs.push({ kind: row.kind, chain: [...row.chain], values: [row.value] });
    }
  }
  return runs.map((run) => {
    const item: SelectorItem = { [run.kind]: run.values.length === 1 ? run.values[0] : run.values };
    if (run.chain.length > 0) item.through = run.chain;
    return item;
  });
}

const quote = (s: string) => `"${s}"`;
const list = (xs: string[]) => (xs.length === 1 ? quote(xs[0]) : `[${xs.map(quote).join(', ')}]`);

/**
 * The field as it will be written — the selector form, never a resolved name.
 *
 * Shown to the author so the control's effect on the document is visible while editing, rather
 * than only after a save.
 */
export function documentText(rows: SelectorRow[]): string {
  const items = collapse(rows);
  if (items.length === 0) return '[]';
  return items
    .map((item) => {
      const kind = Object.keys(item).find((k) => k !== 'through');
      if (kind === undefined) return '{}';
      const values = list(asList(item[kind]));
      const through = item.through?.length ? `, through = ${list(item.through)}` : '';
      return `{${kind} = ${values}${through}}`;
    })
    .join(', ');
}
