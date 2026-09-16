import {
  createStore, reconcile, snapshot,
  type Store, type StoreSetter,
} from "solid-js";
import { persisted, persistedSignal } from "./persist";

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

const loader = persisted<LoaderStore>("dashi.loader", [] as LoaderStore);
export const LOADER_STORE: [Store<LoaderStore>, StoreSetter<LoaderStore>] = [loader[0], loader[1]];
/** The loaded source, serialised once — as `CARDS_JSON` is for the document. The preview keys on
 *  it to know a *different* source is in the store, which its column list cannot say. */
export const LOADER_JSON = loader[2];

export type FiltersStore = {
  numerical: { [key: string]: Interval | null };
  categorical: { [key: string]: List | null };
};

/** `Interval` and `Set` are not JSON; carried as `{min,max}` and arrays, rebuilt on the way in. */
export const filtersCodec = {
  encode: (v: FiltersStore) => ({
    numerical: Object.fromEntries(Object.entries(v.numerical).map(([k, i]) => [k, i && { min: i.min, max: i.max }])),
    categorical: Object.fromEntries(Object.entries(v.categorical).map(([k, s]) => [k, s && [...s]])),
  }),
  decode: (raw: unknown): FiltersStore => {
    const r = raw as { numerical?: Record<string, { min: number; max: number } | null>; categorical?: Record<string, unknown[] | null> };
    return {
      numerical: Object.fromEntries(Object.entries(r.numerical ?? {}).map(([k, i]) => [k, i && new Interval(i.min, i.max)])),
      categorical: Object.fromEntries(Object.entries(r.categorical ?? {}).map(([k, l]) => [k, l && new Set(l)])),
    };
  },
};
const filters = persisted<FiltersStore>("dashi.filters", { numerical: {}, categorical: {} }, filtersCodec);
export const FILTERS_STORE: [Store<FiltersStore>, StoreSetter<FiltersStore>] = [filters[0], filters[1]];

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
  /** How bad: an error blocks the run; a warning (a column about to be overwritten) does not.
   *  Absent from an older server means error. */
  severity?: "error" | "warning";
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

/** The issues addressing one group — `/groups/<name>` and anything below it. */
export function issuesForGroup(issues: ProbeIssue[], name: string): ProbeIssue[] {
  const want = ["", "groups", name.replace(/~/g, "~0").replace(/\//g, "~1")];
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

// Not persisted: it is derived from the document and recomputes within 200 ms of load (Task 6).
// Persisting it would cost a write per probe for a value that is about to be replaced.
export const PROBE_STORE = createStore<ProbeStore>(emptyProbe());

/**
 * A run that failed to build says where, in the probe's shape — so the cards show it as they
 * show a probe finding. Written into `PROBE_STORE` rather than kept by the results pane: the
 * cards already read one place, and the next edit's probe replaces this as it replaces any result.
 */
export function reportRunIssues(issues: ProbeIssue[]) {
  const [, setProbe] = PROBE_STORE;
  setProbe((draft) => {
    draft.valid = false;
    draft.issues = issues;
  });
}

const cardsPersisted = persisted<CardsStore>("dashi.cards", emptyCards());
export const CARDS_STORE: [Store<CardsStore>, StoreSetter<CardsStore>] = [cardsPersisted[0], cardsPersisted[1]];
/** The document, serialised once. Persistence writes it; the probe (Task 6) keys on it. */
export const CARDS_JSON = cardsPersisted[2];

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

/**
 * Every selector item in the document, with a callback that returns the item to keep — or
 * `null` to drop it.
 *
 * A selector is *structural*: any array whose objects carry `cols` / `groups` / `nodes` /
 * `through`. Walked that way rather than by asking the IR which fields are selectors, so a field
 * this UI has never heard of is covered too. Items left with no value are dropped, and a group's
 * own selector list is walked like a card's — groups may name groups.
 */
function forEachSelector(draft: CardsStore, edit: (item: Selector) => Selector | null) {
  const isSelector = (v: unknown): v is Selector[] =>
    Array.isArray(v) && v.every((x) => x && typeof x === "object" &&
      ["cols", "groups", "nodes", "through"].some((k) => k in (x as object)));
  const walk = (holder: Record<string, unknown>) => {
    for (const [key, value] of Object.entries(holder)) {
      if (isSelector(value)) {
        holder[key] = value.map(edit).filter((item): item is Selector => item !== null);
      } else if (value && typeof value === "object" && !Array.isArray(value)) {
        walk(value as Record<string, unknown>);
      }
    }
  };
  for (const node of draft.nodes) walk(node.card as Record<string, unknown>);
  for (const name of Object.keys(draft.groups)) {
    draft.groups[name] = draft.groups[name].map(edit).filter((item): item is Selector => item !== null);
  }
}

/** `{kind: value}` with `name` taken out of the kind's one-or-many value; `null` when nothing is left. */
function dropName(item: Selector, kind: "groups" | "nodes", name: string): Selector | null {
  const out: Selector = { ...item };
  const value = out[kind];
  const rest = (Array.isArray(value) ? value : value === undefined ? [] : [value]).filter((v) => v !== name);
  if (Array.isArray(value) || value === undefined) { if (rest.length === 0) delete out[kind]; else out[kind] = rest; }
  else if (value === name) delete out[kind];
  if (Array.isArray(out.through)) {
    out.through = out.through.filter((v) => v !== name);
    if (out.through.length === 0) delete out.through;
  }
  return "cols" in out || "groups" in out || "nodes" in out ? out : null;
}

function renameIn(item: Selector, kind: "groups" | "nodes", from: string, to: string): Selector {
  const out: Selector = { ...item };
  const value = out[kind];
  if (Array.isArray(value)) out[kind] = value.map((v) => (v === from ? to : v));
  else if (value === from) out[kind] = to;
  if (Array.isArray(out.through)) out.through = out.through.map((v) => (v === from ? to : v));
  return out;
}

export function removeGroup(name: string) {
  setCards((draft) => {
    delete draft.groups[name];
    forEachSelector(draft, (item) => dropName(item, "groups", name));
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
    forEachSelector(draft, (item) => renameIn(item, "groups", from, to));
  });
  return renamed;
}

/** Rename a node. The card is untouched: the id belongs to the wrapper, not the card. */
export function setNodeId(nodeIndex: number, id: string) {
  setCards((draft) => {
    const from = draft.nodes[nodeIndex].id;
    draft.nodes[nodeIndex].id = id;
    if (from && from !== id) forEachSelector(draft, (item) => renameIn(item, "nodes", from, id));
  });
}

export function removeNode(nodeIndex: number) {
  setCards((draft) => {
    const id = draft.nodes[nodeIndex]?.id;
    draft.nodes.splice(nodeIndex, 1);
    if (id) forEachSelector(draft, (item) => dropName(item, "nodes", id));
  });
}

// --- confirmation --------------------------------------------------------------------------
//
// Which definitions the author has deliberately marked finished.
//
// Not in the document and not sent anywhere: this is an ergonomic mark. It is kept in
// `sessionStorage` beside the document it describes, so a reload brings both back and the marks
// still stand against the cards they were made on; closing the tab ends them, as it ends the
// document.
//
// Stored as a *signature of the content* rather than a flag. Editing a confirmed card changes its
// signature and so un-confirms it automatically, which is the behaviour that matters: a card
// confirmed and then changed is no longer something anyone declared finished, and a flag would go
// quietly stale instead. It is also what makes the keys safe: they are node *indices*, so removing
// an earlier card slides every later mark onto its neighbour — where it no longer matches, and so
// reads as unconfirmed rather than as somebody else's approval.

const [confirmations, setConfirmations] = persistedSignal<Record<string, string>>("dashi.confirmations", {});

const signatureOf = (value: unknown) => JSON.stringify(value);

export function isConfirmed(key: string, value: unknown): boolean {
  return confirmations()[key] === signatureOf(value);
}

export function confirmDefinition(key: string, value: unknown) {
  setConfirmations({ ...confirmations(), [key]: signatureOf(value) });
}

export function forgetConfirmation(key: string) {
  const next = { ...confirmations() };
  delete next[key];
  setConfirmations(next);
}
