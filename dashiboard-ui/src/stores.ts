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

/** The nodes and groups an item can refer to without making a loop. */
export type Referable = { nodes: string[]; groups: string[] };

export type ProbeStore = {
  valid: boolean;
  cols: string[];
  nodes: ProbeNode[];
  errors: string[];
  issues: ProbeIssue[];
  /** Per card, by index, and per group, by name; `null` when the server could not say. */
  referable: { nodes: Referable[]; groups: Record<string, Referable> } | null;
};

export const emptyProbe = (): ProbeStore => ({
  valid: true,
  cols: [],
  nodes: [],
  errors: [],
  issues: [],
  referable: null,
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
 * A server's pointed issues, as rejected verdicts on the items they point at.
 *
 * The one bridge from issues to red. A failed run and an upload both come through here, so an
 * issue is placed the same way whoever asked; Confirm places its own through `issueFindings`
 * with the same shape. A Run or an upload is the author asking, exactly as Confirm is, so red is
 * right here where it would not be for the continuous probe. Warnings are not findings and are
 * skipped. An issue whose pointer names no item is not this function's to place —
 * `documentFindings` reads those.
 *
 * `document` is what the server was *sent*, not the store as it is when the reply lands: the
 * author may have edited in between, and a verdict on content the server never saw is the one
 * thing a verdict must never be. Defaults to the current document for callers with no request
 * in flight.
 *
 * Writes verdicts and nothing else. It used to write `PROBE_STORE` too, outside the continuous
 * probe's `probeSeq` guard, so an older probe reply landing afterwards erased a failed run's
 * issues from the store (measured 2026-09-17). The store has one writer now.
 */
export function rejectFromIssues(
  issues: ProbeIssue[],
  document: Pick<CardsStore, "nodes" | "groups"> = exportCards(),
) {
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
 * What a probe reply says about the *document* rather than about any item.
 *
 * The server reports in layers: schema failures and empty groups come back pointed at an item,
 * before building; build faults — a loop, two cards with one id, a `through` chain nothing can
 * resolve — come back as `errors` with `issues: []`. So `errors` belong to the document exactly
 * when the document does not build and no error issue names an item. Otherwise they are the
 * items' own messages run together (a schema failure's `errors` is that concatenation), already
 * read on the items, and confirming an unrelated card must still go green. An issue whose
 * pointer names no item counts as the document's too; none is emitted today.
 */
export function documentFindings(
  answer: Pick<ProbeStore, "valid" | "issues" | "errors">,
): Incompleteness[] {
  const errors = answer.issues.filter((issue) => issue.severity !== "warning");
  const loose = errors.filter((issue) => itemKey(issue.pointer) === null);
  const anyPointed = errors.length > loose.length;
  const findings: Incompleteness[] = loose.map((issue) => ({ message: issue.message }));
  if (answer.valid === false && !anyPointed) {
    // `errors` repeats the issues' messages (a loop arrives as one issue pointing at no item,
    // and `errors` holding that same sentence), so only what was not already said is added.
    const said = new Set(findings.map((finding) => finding.message));
    findings.push(...answer.errors.filter((message) => !said.has(message)).map((message) => ({ message })));
  }
  return findings;
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
function forEachSelector(draft: CardsStore, edit: (item: Selector, where: string) => Selector | null) {
  const isItem = (x: unknown): x is Selector =>
    !!x && typeof x === "object" && ["cols", "groups", "nodes", "through"].some((k) => k in (x as object));
  const isSelector = (v: unknown): v is Selector[] => Array.isArray(v) && v.every(isItem);
  const walk = (holder: Record<string, unknown>, where: string) => {
    for (const [key, value] of Object.entries(holder)) {
      if (isSelector(value)) {
        holder[key] = value.map((item) => edit(item, where)).filter((item): item is Selector => item !== null);
      } else if (!Array.isArray(value) && isItem(value)) {
        // Tested before the recursion below, which would otherwise descend past it into `cols`.
        const next = edit(value, where);
        if (next === null) delete holder[key]; else holder[key] = next;
      } else if (value && typeof value === "object" && !Array.isArray(value)) {
        walk(value as Record<string, unknown>, where);
      }
    }
  };
  draft.nodes.forEach((node, index) =>
    walk(node.card as Record<string, unknown>, node.id || `card ${index + 1}`));
  for (const name of Object.keys(draft.groups)) {
    draft.groups[name] = draft.groups[name]
      .map((item) => edit(item, `group ${name}`))
      .filter((item): item is Selector => item !== null);
  }
}

export type DroppedReference = { what: string; where: string };
/** What the last table or document load removed, for the Process tab to say. Transient. */
export const [droppedReferences, setDroppedReferences] = createSignal<DroppedReference[]>([]);

/**
 * Remove references to columns the loaded table lacks and to nodes and groups the document
 * lacks, and return them. No table loaded means columns cannot be judged, so they stay. A
 * reference that exists is never removed here, even when it makes a loop. Given a `target`, that
 * plain document is pruned in place of the store — for a document not yet stored.
 */
export function pruneReferences(columns: readonly string[] | null, target?: CardsStore): DroppedReference[] {
  const dropped: DroppedReference[] = [];
  const prune = (draft: CardsStore) => {
    const present: Record<"cols" | "nodes" | "groups", Set<string> | null> = {
      cols: columns !== null && columns.length > 0 ? new Set(columns) : null,
      nodes: new Set(draft.nodes.map((node) => node.id ?? "")),
      groups: new Set(Object.keys(draft.groups)),
    };
    forEachSelector(draft, (item, where) => {
      const out: Selector = { ...item };
      for (const kind of ["cols", "nodes", "groups"] as const) {
        const known = present[kind];
        const value = out[kind];
        if (known === null || value === undefined) continue;
        const kept = (Array.isArray(value) ? value : [value]).filter((name) => {
          if (!known.has(name)) dropped.push({ what: `${kind}:${name}`, where });
          return known.has(name);
        });
        if (kept.length === 0) delete out[kind];
        else out[kind] = kept.length === 1 ? kept[0] : kept;
      }
      // An item with no value left goes whole; its chain is not a loss of its own.
      if (!("cols" in out || "groups" in out || "nodes" in out)) return null;
      if (Array.isArray(out.through)) {
        out.through = out.through.filter((step) => {
          if (!present.nodes!.has(step)) dropped.push({ what: `@${step}`, where });
          return present.nodes!.has(step);
        });
        if (out.through.length === 0) delete out.through;
      }
      return out;
    });
  };
  if (target === undefined) setCards(prune); else prune(target);
  return dropped;
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

/** `item` with `from` replaced by `to`, in the kind's value and in a `through` chain. */
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

/**
 * Rename a node, and refuse a name another card already has.
 *
 * The card is untouched: the id belongs to the wrapper, not the card. Two cards with one name is a
 * document the server cannot build, and it says so with no pointer (measured 2026-09-17:
 * `Encountered nodes with equal \`id\``, `issues: []`), so no card could carry the finding —
 * refused here instead, as `renameGroup` refuses a second group's name. A missing id counts as
 * "": that is `Pipelines.get_id`'s default, so two unnamed cards collide the same way. One
 * unnamed card is still legal, and Confirm is what objects to it (`checkNode`).
 */
export function setNodeId(nodeIndex: number, id: string): boolean {
  let renamed = false;
  setCards((draft) => {
    // Read `draft`, not `cards`: see `addGroup`.
    if (draft.nodes.some((node, at) => at !== nodeIndex && (node.id ?? "") === id)) return;
    renamed = true;
    const from = draft.nodes[nodeIndex].id;
    draft.nodes[nodeIndex].id = id;
    if (from && from !== id) forEachSelector(draft, (item) => renameIn(item, "nodes", from, id));
  });
  return renamed;
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

// --- the document's own verdict ---------------------------------------------------------------
// A relational fault — a loop, a `through` chain nothing can resolve — belongs to no card: seen in
// a browser (2026-09-18) written on every card that happened to be asked, and again under the
// document row. It gets a verdict of its own, keyed on the whole cards document and bound to its
// content like any other, so it is said once (next to Run pipeline), only after somebody asked
// (a Confirm, a load, a failed run), and any edit expires it.
const DOCUMENT_KEY = "document";

/** Record that the server refused this document, with its sentences. */
export function rejectDocument(
  document: Pick<CardsStore, "nodes" | "groups">,
  findings: Incompleteness[],
) {
  // `nodes` then `groups`, whatever order the document arrived in (a loaded file may say
  // `groups` first): the signature is compared with the store's own serialisation.
  recordVerdict(DOCUMENT_KEY, { nodes: document.nodes, groups: document.groups }, "rejected", findings);
}

/** The verdict on the cards document as it is now — null once anything in it is edited. */
export function documentVerdict(): Verdict | null {
  // `CARDS_JSON` is the store's serialisation, the very string a snapshot's signature is; a
  // tracked read, so a caller in a memo re-runs on every edit.
  const v = verdicts()[DOCUMENT_KEY];
  return v !== undefined && v.signature === CARDS_JSON() ? v : null;
}

// How many times each key's verdict has been taken away — by a removal, a rename, a forget.
// A question asked of an item is only worth recording while this has not moved: content cannot
// tell a removed group from a new one of the same name (`[]` is `[]`), so an answer that arrived
// late used to mark a group nobody had asked about (measured 2026-09-17, again 2026-09-21; it
// takes a slow server to show). Plain, not reactive: it is read once before a request and once
// after, never rendered.
const retired = new Map<string, number>();
const retire = (key: string) => retired.set(key, (retired.get(key) ?? 0) + 1);

/** A token for "this item as it is asked about now"; see `stillAsked`. */
export const askedOf = (key: string) => retired.get(key) ?? 0;
/** False once the item the question was about has been removed, renamed or forgotten since. */
export const stillAsked = (key: string, token: number) => askedOf(key) === token;

export function forgetVerdict(key: string) {
  retire(key);
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
  // Every position from the removed one on now holds a different card, so a question still in
  // flight about any of them is about a card that is no longer there (see `retired`).
  for (let at = removed; at <= cards.nodes.length; at++) retire(`node:${at}`);
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
  retire(from);
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
