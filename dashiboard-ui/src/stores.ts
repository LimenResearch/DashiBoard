import { createStore, reconcile, snapshot } from "solid-js";

export class Interval {
  min: number;
  max: number;

  constructor(min: number, max: number) {
    this.min = min;
    this.max = max;
  }

  clone() {
    return new Interval(this.min, this.max);
  }
}

export type List = Set<any>;

// One entry per column of the loaded source, as `load-files` returns it.
//
// `type` is the filter family and `summary` depends on it — DataIngestion aggregates a numerical
// column to `(min, max)` and a categorical one to its distinct values. Modelling that as a union
// rather than as `any` is what lets a filter component say which shape it accepts; it is also how
// `<For each={numerical()}>{IntervalFilter}</For>` gets checked at all.
//
// `eltype` is the storage type, a separate and wider vocabulary — bool, date, datetime, float,
// int, string, time — and it is what decides formatting rather than filtering.

export type NumericalSummary = {
  name: string;
  type: "numerical";
  eltype: string;
  /** `step` is not sent; it stays optional for callers that know a column's grid. */
  summary: { min: number; max: number; step?: number };
};

export type CategoricalSummary = {
  name: string;
  type: "categorical";
  eltype: string;
  summary: unknown[];
};

export type VariableSummary = NumericalSummary | CategoricalSummary;

export type LoaderStore = VariableSummary[];

export const LOADER_STORE = createStore<LoaderStore>([] as LoaderStore);

export type FiltersStore = {
  numerical: { [key: string]: Interval | null };
  categorical: { [key: string]: List | null };
};

export const FILTERS_STORE = createStore<FiltersStore>({
  numerical: {},
  categorical: {},
} as FiltersStore);

// The authored half of the ExperimentTracking `Config` — `{nodes, groups}`. Filters live in
// FILTERS_STORE and are converted at the wire boundary by `getFilters`, following the same
// store-plus-getter split as the rest of this file.
//
// This store IS the document, rather than a bag of widget values: decisions section 2 requires
// that what gets saved is the authored JSON and never a reconstruction, because by the time
// `Card`s exist the group vocabulary has been resolved away and `StructUtils.lower` emits nulls
// the schema forbids. Nothing saves to a registry yet (B6), so the cost of the widget-value shape
// would only arrive later — which is exactly why it is cheaper to not adopt it now.

export type Selector = {
  nodes?: string | string[];
  groups?: string | string[];
  cols?: string | string[];
  through?: string[];
};

export type Card = { type: string } & { [key: string]: unknown };

export type PipelineNode = { id?: string; card: Card } & { [key: string]: unknown };

export type CardsStore = {
  nodes: PipelineNode[];
  groups: { [name: string]: Selector[] };
  // Load-bearing: a stored document may carry keys this UI has never heard of — a format
  // `version`, say — and they must survive a round trip untouched.
  [key: string]: unknown;
};

export const emptyCards = (): CardsStore => ({ nodes: [], groups: {} });

// What `POST /probe-pipeline` last reported: each node's resolved inputs and outputs, and any
// reference nothing produces (A10).
//
// The resolved names come from Julia. A `through` chain names a column by concatenating the
// suffixes of the nodes it lists, and reimplementing that here would be a second source of truth
// for a naming rule — the duplication this refactor exists to remove. The UI writes the document;
// DashiBoard resolves it and says what it got.

export type ProbeNode = {
  id: string;
  inputs: string[];
  outputs: string[];
  unproduced: string[];
};

/**
 * One failure, as data rather than prose (A7). `pointer` is a JSON Pointer into the *document*,
 * so the form can address the offending control instead of printing a sentence above the page.
 *
 * `allowed` carries what the schema would have accepted — the difference between offering a
 * correction and saying no. `missing` carries names that should exist and do not: absent required
 * properties, or, when `reason` is "unproduced", columns nothing in the pipeline emits.
 */
export type ProbeIssue = {
  pointer: string;
  reason: string;
  found: unknown;
  allowed: unknown[] | null;
  missing: string[];
  related: string[];
  message: string;
};

export type ProbeStore = {
  valid: boolean;
  cols: string[];
  nodes: ProbeNode[];
  errors: string[];
  issues: ProbeIssue[];
};

export const emptyProbe = (): ProbeStore => ({
  valid: true,
  cols: [],
  nodes: [],
  errors: [],
  issues: [],
});

/**
 * The issues addressing one node.
 *
 * Matched on the pointer's segments rather than as a string prefix: `/nodes/1/…` is a prefix of
 * `/nodes/12/…` textually, and would silently attach node 12's failures to node 1.
 */
export function issuesForNode(issues: ProbeIssue[], nodeIndex: number): ProbeIssue[] {
  const want = ["", "nodes", String(nodeIndex), "card"];
  return issues.filter((issue) => {
    const parts = issue.pointer.split("/");
    return want.every((segment, i) => parts[i] === segment);
  });
}

const unescapeToken = (token: string) => token.replace(/~1/g, "/").replace(/~0/g, "~");

/**
 * The part of a pointer below the card, as something a person can read.
 *
 * A JSON Pointer counts array positions from zero, which is right on the wire and wrong on
 * screen: nobody reading "the 3rd input" wants to be told "2". Numeric segments are shifted back
 * for display only — the pointer itself is never rewritten.
 */
export function fieldPath(pointer: string): string {
  return pointer
    .split("/")
    .slice(4) // "", "nodes", "<i>", "card"
    .map((token) => (/^\d+$/.test(token) ? String(Number(token) + 1) : unescapeToken(token)))
    .join(" → ");
}

export const PROBE_STORE = createStore<ProbeStore>(emptyProbe());

export const CARDS_STORE = createStore<CardsStore>(emptyCards());

const [cards, setCards] = CARDS_STORE;

/** Replace the authored document. Stored verbatim, including keys we do not model. */
export function importCards(value: CardsStore) {
  setCards(reconcile(structuredClone(value)));
}

/**
 * The document as it would be saved. `snapshot` unwraps the reactive proxy; `structuredClone`
 * makes the result independent of later edits.
 */
export function exportCards(): CardsStore {
  return structuredClone(snapshot(cards)) as CardsStore;
}

/** Replace a whole card. This is what an IRField edit produces: the object, not a key. */
export function setCard(nodeIndex: number, card: Card) {
  setCards((draft) => {
    draft.nodes[nodeIndex].card = card;
  });
}

export function setCardField(nodeIndex: number, key: string, value: unknown) {
  setCards((draft) => {
    draft.nodes[nodeIndex].card[key] = value;
  });
}

/**
 * A name no surviving node holds, derived from the card type: `split`, then `split_2`.
 *
 * Not cosmetic. `Pipelines.get_id` defaults a missing `id` to `""`, so two unnamed nodes are
 * duplicates and `dependency_graph` rejects the whole document — and a node with no name cannot
 * be named by another card's `nodes:` selector or `through:` chain at all.
 */
function freshId(type: string, taken: Set<string>): string {
  if (!taken.has(type)) return type;
  for (let n = 2; ; n++) {
    const candidate = `${type}_${n}`;
    if (!taken.has(candidate)) return candidate;
  }
}

export function addNode(card: Card, id?: string) {
  setCards((draft) => {
    const taken = new Set(draft.nodes.map((node) => node.id).filter((x): x is string => !!x));
    draft.nodes.push({ id: id ?? freshId(card.type, taken), card });
  });
}

/**
 * Create a group, empty, and return the name it was given.
 *
 * Empty is a legal state — measured: `weather = []` constructs — which is what lets a group be
 * named before it holds anything. That order is forced rather than chosen: a group is referred to
 * by name, so until it has one there is nothing for a card's `groups:` selector to name.
 */
export function addGroup(name?: string): string {
  // The name is chosen from `draft`, not from `cards`. A store write is applied to the draft
  // synchronously but *notified* later, so a `cards` read here sees the state before the previous
  // call — and two groups added in a row would both come out `group`.
  let chosen = name ?? "";
  setCards((draft) => {
    chosen = name ?? freshId("group", new Set(Object.keys(draft.groups)));
    draft.groups[chosen] = [];
  });
  return chosen;
}

/** Replace a group's selectors. Same shape as a card's `inputs`, hence the same picker. */
export function setGroup(name: string, items: Selector[]) {
  setCards((draft) => {
    draft.groups[name] = items;
  });
}

export function removeGroup(name: string) {
  setCards((draft) => {
    delete draft.groups[name];
  });
}

/**
 * Rename a group, keeping its position among the others, and refuse a name already taken.
 *
 * Rebuilt rather than deleted-and-reinserted because JavaScript orders object keys by insertion:
 * the shortcut sends the renamed group to the end of the list, which reads as it having been
 * recreated. Refusing a collision matters more — the shortcut there silently merges two groups
 * into one, losing the contents of whichever was written second.
 */
export function renameGroup(from: string, to: string): boolean {
  if (from === to) return true;
  if (to === "") return false;
  let renamed = false;
  setCards((draft) => {
    // Read `draft`, not `cards`: see `addGroup`. Checking the stale copy would let a rename onto
    // a group created moments earlier through, which is the merge this refuses.
    if (Object.hasOwn(draft.groups, to)) return;
    renamed = true;
    draft.groups = Object.fromEntries(
      Object.entries(draft.groups).map(([key, value]) => [key === from ? to : key, value]),
    );
  });
  return renamed;
}

/** Rename a node. The card is untouched: the id belongs to the wrapper, not the card. */
export function setNodeId(nodeIndex: number, id: string) {
  setCards((draft) => {
    draft.nodes[nodeIndex].id = id;
  });
}

export function removeNode(nodeIndex: number) {
  setCards((draft) => {
    draft.nodes.splice(nodeIndex, 1);
  });
}
