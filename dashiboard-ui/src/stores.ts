import {
  createSignal, createStore, reconcile, snapshot,
  type Store, type StoreSetter,
} from "solid-js";
import { persisted, persistedSignal } from "./persist";
import type { Incompleteness } from "./completeness";
import { issueFindings } from "./findings";

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

/**
 * Which filters the last load dropped, by column — for the Filter tab to say so. Transient: a
 * notice, not part of the document.
 */
export const [droppedFilters, setDroppedFilters] = createSignal<string[]>([]);

/**
 * Drop every filter whose column the loaded table lacks, and say which.
 *
 * A filter is authored against a table; load a table without that column and the filter cannot
 * apply — the run fails on it (measured 2026-09-16: a list filter on `cbwd` over
 * `pollution_test.parquet`). Keeping it and asking the author to remove it is friction; clearing
 * every filter whenever the column set changes (the earlier heuristic) threw away the ones that
 * still applied, silently. So: remove exactly the ones that cannot apply, keep the rest, and
 * return the names so the Filter tab can announce them.
 *
 * No summaries means no table is loaded, and a document's filters cannot be judged against
 * nothing — they stay.
 */
export function pruneFilters(summaries: readonly { name: string }[]): string[] {
  if (summaries.length === 0) return [];
  const present = new Set(summaries.map((s) => s.name));
  const dropped: string[] = [];
  const [, setFilters] = FILTERS_STORE;
  setFilters((draft) => {
    for (const kind of ["numerical", "categorical"] as const) {
      for (const name of Object.keys(draft[kind])) {
        if (!present.has(name)) {
          delete draft[kind][name];
          dropped.push(name);
        }
      }
    }
  });
  if (dropped.length > 0) setDroppedFilters(dropped);
  return dropped;
}

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
 * A run that failed to build says where, in the probe's shape.
 *
 * Written into `PROBE_STORE` — the pointer next to Run pipeline reads it — and recorded as a
 * *rejected* verdict on every item an error points at: a Run is the author asking, exactly as
 * Confirm is, so red is right here where it would not be for the continuous probe. Warnings are
 * not rejections. The findings are derived as Confirm derives them, so the item reads the same
 * whoever asked.
 *
 * `document` is what the run was *sent*, not the store as it is when the reply lands: the author
 * may have edited in between, and a verdict on content the server never saw is the one thing a
 * verdict must never be. Defaults to the current document for callers with no request in flight.
 */
export function reportRunIssues(
  issues: ProbeIssue[],
  document: Pick<CardsStore, "nodes" | "groups"> = exportCards(),
) {
  const [, setProbe] = PROBE_STORE;
  setProbe((draft) => {
    draft.valid = false;
    draft.issues = issues;
  });
  const byItem = new Map<string, ProbeIssue[]>();
  for (const issue of issues) {
    if (issue.severity === "warning") continue;
    const key = itemKey(issue.pointer);
    if (key === null) continue;
    byItem.set(key, [...(byItem.get(key) ?? []), issue]);
  }
  for (const [key, own] of byItem) {
    const value = itemValue(key, document);
    if (value === undefined) continue;
    recordVerdict(key, value, "rejected", issueFindings(own));
  }
}

/** `/nodes/<i>/…` → `node:<i>`; `/groups/<name>/…` → `group:<name>`; anything else → null. */
export function itemKey(pointer: string): string | null {
  const parts = pointer.split("/");
  if (parts[1] === "nodes" && parts[2] !== undefined) return `node:${parts[2]}`;
  if (parts[1] === "groups" && parts[2] !== undefined) return `group:${unescapeToken(parts[2])}`;
  return null;
}

/**
 * The content a verdict on `key` binds to: the whole node (its id is part of what was checked —
 * `checkNode` judges it, and the server reports duplicates), or the group's selector list.
 */
function itemValue(key: string, document: Pick<CardsStore, "nodes" | "groups">): unknown {
  if (key.startsWith("node:")) return document.nodes[Number(key.slice(5))];
  if (key.startsWith("group:")) return document.groups[key.slice(6)];
  return undefined;
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
 *
 * A lone selector object counts too: the IR's `$defs/variable` fields — `partition`, `weights`,
 * `gaussian_encoding.input`, `interp.input`, `glm.formula.target` — hold one, not a list, and an
 * array-only walk left `partition: {groups: "g"}` naming a group that had just been removed.
 */
function forEachSelector(draft: CardsStore, edit: (item: Selector) => Selector | null) {
  const isItem = (x: unknown): x is Selector =>
    !!x && typeof x === "object" && ["cols", "groups", "nodes", "through"].some((k) => k in (x as object));
  const isSelector = (v: unknown): v is Selector[] => Array.isArray(v) && v.every(isItem);
  const walk = (holder: Record<string, unknown>) => {
    for (const [key, value] of Object.entries(holder)) {
      if (isSelector(value)) {
        holder[key] = value.map(edit).filter((item): item is Selector => item !== null);
      } else if (!Array.isArray(value) && isItem(value)) {
        // Tested before the recursion below, which would otherwise descend past it into `cols`.
        const next = edit(value);
        if (next === null) delete holder[key]; else holder[key] = next;
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
  // Or a later group under the same name and the same content would inherit an answer nobody
  // asked for it — red before its first Confirm, and across a reload.
  forgetVerdict(`group:${name}`);
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
  // The content is unchanged, so what the server said about it still stands — under the new name.
  if (renamed) moveVerdict(`group:${from}`, `group:${to}`);
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
  shiftVerdictsPast(nodeIndex);
}

// --- verdicts -------------------------------------------------------------------------------
//
// What the author has asked about each definition, and what the server answered.
//
// Not in the document and not sent anywhere: an ergonomic mark, kept in `sessionStorage` beside
// the document so a reload brings both back, with the findings the answer came with; closing
// the tab ends them, as it ends the document.
//
// A verdict is bound to a *signature of the content*, never a flag. Editing an item changes its
// signature, so green and red alike expire on edit — the item is back to "not asked" until the
// next Confirm — and nothing stays wrong or right by memory about content the server never saw.
//
// Cards are keyed by *position* (there is nothing in the document to make a stable key from),
// so `removeNode` slides every later card's verdict down with it (`shiftVerdictsPast`): a
// precise field pointer attached to the wrong card would be worse than no pointer at all. The
// signature check is the safety net beneath that — a key that lands on the wrong content reads
// as unasked, never as somebody else's answer.
//
// Decided 2026-09-17: red is reserved for "you asked, and it was wrong". The continuous probe
// never writes here; only Confirm and a Run do.

export type Verdict = {
  signature: string;
  verdict: "confirmed" | "rejected";
  findings: Incompleteness[];
};

const [verdicts, setVerdicts] = persistedSignal<Record<string, Verdict>>("dashi.verdicts", {});

const signatureOf = (value: unknown) => JSON.stringify(value);

/** The verdict on `key`, only if it was given on exactly `value`; `null` otherwise. */
export function verdictOf(key: string, value: unknown): Verdict | null {
  const v = verdicts()[key];
  return v !== undefined && v.signature === signatureOf(value) ? v : null;
}

export function isConfirmed(key: string, value: unknown): boolean {
  return verdictOf(key, value)?.verdict === "confirmed";
}

export function recordVerdict(
  key: string,
  value: unknown,
  verdict: Verdict["verdict"],
  findings: Incompleteness[] = [],
) {
  // A functional updater, not `{...verdicts(), ...}`: Solid 2 stages a signal write, so a plain
  // read right after a write in the same tick still returns the pre-write value — two calls back
  // to back would each build their map off the same stale read, and the second would be the only
  // edit to survive a flush. An updater chains off the previous updater's return instead.
  setVerdicts((prev) => ({ ...prev, [key]: { signature: signatureOf(value), verdict, findings } }));
}

/** A plain "confirmed" verdict, for callers that only ever say yes. */
export function confirmDefinition(key: string, value: unknown) {
  recordVerdict(key, value, "confirmed");
}

export function forgetVerdict(key: string) {
  setVerdicts((prev) => {
    const next = { ...prev };
    delete next[key];
    return next;
  });
}

export const forgetConfirmation = forgetVerdict;

/**
 * After `nodes[removed]` is spliced out, the verdicts of the cards behind it move down one —
 * and so do the `/nodes/<i>/…` pointers in their findings, so a control lookup through a finding
 * lands on the card it was made about.
 */
function shiftVerdictsPast(removed: number) {
  setVerdicts((prev) => {
    const next: Record<string, Verdict> = {};
    for (const [key, value] of Object.entries(prev)) {
      if (!key.startsWith("node:")) {
        next[key] = value;
        continue;
      }
      const at = Number(key.slice(5));
      if (at < removed) next[key] = value;
      else if (at > removed) {
        next[`node:${at - 1}`] = {
          ...value,
          findings: value.findings.map((finding) =>
            finding.pointer?.startsWith(`/nodes/${at}/`)
              ? { ...finding, pointer: finding.pointer.replace(`/nodes/${at}/`, `/nodes/${at - 1}/`) }
              : finding,
          ),
        };
      }
    }
    return next;
  });
}

function moveVerdict(from: string, to: string) {
  setVerdicts((prev) => {
    if (prev[from] === undefined) return prev;
    const next = { ...prev, [to]: prev[from] };
    delete next[from];
    return next;
  });
}

export function forgetAllVerdicts() {
  setVerdicts(() => ({}));
}
