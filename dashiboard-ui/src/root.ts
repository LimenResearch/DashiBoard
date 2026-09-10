import { createRoot, createStore, reconcile, snapshot } from "solid-js";

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

type LoaderStore = string[];

type FiltersStore = {
  numerical: { [key: string]: Interval | null };
  categorical: { [key: string]: List | null };
};

export const loader_store = createRoot((dispose) => {
  const [state, setState] = createStore<LoaderStore>([] as LoaderStore);
  return { state, setState, dispose };
});

export const filters_store = createRoot((dispose) => {
  const [state, setState] = createStore<FiltersStore>({
    numerical: {},
    categorical: {},
  } as FiltersStore);
  return { state, setState, dispose };
});

// The authored ExperimentTracking `Config` — `{filters, nodes, groups}`.
//
// This store IS the document. Widgets are views over it, and what gets saved is this object
// rather than a reconstruction from widget state (decisions section 2): by the time `Card`s
// exist the group vocabulary has been resolved away — `inputs` comes back as ["PRES","TEMP"]
// instead of {cols = [...]} — and `StructUtils.lower` emits nulls the schema forbids, so a
// rebuilt document is invalid on two counts.

export type Selector = {
  nodes?: string | string[];
  groups?: string | string[];
  cols?: string | string[];
  through?: string[];
};

export type Card = { type: string } & { [key: string]: unknown };

export type PipelineNode = { id?: string; card: Card } & { [key: string]: unknown };

export interface Config {
  filters: { [key: string]: unknown }[];
  nodes: PipelineNode[];
  groups: { [name: string]: Selector[] };
  // Load-bearing rather than laziness: a stored document may carry keys this UI has never
  // heard of — a format `version`, say — and they must survive a round trip untouched.
  [key: string]: unknown;
}

export const emptyConfig = (): Config => ({ filters: [], nodes: [], groups: {} });

export const document_store = createRoot((dispose) => {
  const [state, setState] = createStore<Config>(emptyConfig());
  return { state, setState, dispose };
});

/** Replace the whole document. Stored verbatim, including keys we do not model. */
export function importConfig(config: Config) {
  document_store.setState(reconcile(structuredClone(config)));
}

/**
 * The document as it would be saved. `snapshot` unwraps the reactive proxy;
 * `structuredClone` makes the result independent of later edits, so a caller holding an
 * export cannot see the store move under it.
 */
export function exportConfig(): Config {
  return structuredClone(snapshot(document_store.state)) as Config;
}

export function setCardField(nodeIndex: number, key: string, value: unknown) {
  document_store.setState((draft) => {
    draft.nodes[nodeIndex].card[key] = value;
  });
}

const SELECTOR_KEYS = ['nodes', 'groups', 'cols', 'through'];

/** A selector is an object naming variables indirectly, e.g. `{cols: "TEMP"}`. */
function isSelector(value: unknown): boolean {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.keys(value).some((key) => SELECTOR_KEYS.includes(key))
  );
}

/** Does any card field use the group dialect, rather than plain column names? */
function usesSelectors(card: Card): boolean {
  return Object.values(card).some((value) =>
    Array.isArray(value) ? value.some(isSelector) : isSelector(value),
  );
}

/**
 * The request `POST /evaluate-pipeline` accepts, derived from the document, plus whether the
 * document can be previewed there at all.
 *
 * That endpoint takes `{filters, cards}` — the flat shape — while the document we author is the
 * ExperimentTracking `Config` `{filters, nodes, groups}`. Deriving a *run* request is fine; what
 * decisions section 2 forbids is *saving* a reconstruction.
 *
 * The DashiBoard server speaks the flat card API only, and 06-design.md's "Do not do" says not to
 * migrate it to the group API — it is deleted once the new UI serves. Measured against a live
 * server: a flat card returns 200, while `inputs: [{cols: "TEMP"}]` or `[{groups: "weather"}]`
 * returns 500. So a group-dialect document cannot be previewed *at all* — not merely without its
 * groups — and `blocked` says so rather than letting the request fail as a server error.
 *
 * Nothing this UI currently authors can hit that: `/get-card-ir` serves the flat dialect, so the
 * forms produce plain column names. It becomes reachable as soon as importing a saved config does.
 */
export function runRequest(): {
  /** Posted verbatim. Kept separate from the diagnostic so nothing UI-only reaches the server. */
  request: { filters: unknown[]; cards: Card[] };
  /** Why this document cannot be previewed here, or `null` if it can. */
  blocked: string | null;
} {
  const config = exportConfig();
  const cards = config.nodes.map((node) => node.card);
  const groups = Object.keys(config.groups ?? {});
  const withSelectors = cards.filter(usesSelectors).map((card) => String(card.type));

  const reasons: string[] = [];
  if (groups.length > 0) {
    reasons.push(`it defines groups (${groups.join(', ')})`);
  }
  if (withSelectors.length > 0) {
    reasons.push(`these cards use variable selectors rather than column names: ${withSelectors.join(', ')}`);
  }

  return {
    request: { filters: config.filters, cards },
    blocked:
      reasons.length === 0
        ? null
        : `The preview server speaks the flat card API only, so this document cannot be run here — ${reasons.join('; and ')}. Nothing is lost: the document is unchanged.`,
  };
}

/** Replace a whole card. This is what an IRField edit produces: the object, not a key. */
export function setCard(nodeIndex: number, card: Card) {
  document_store.setState((draft) => {
    draft.nodes[nodeIndex].card = card;
  });
}

export function addNode(card: Card, id?: string) {
  document_store.setState((draft) => {
    draft.nodes.push(id === undefined ? { card } : { id, card });
  });
}

export function removeNode(nodeIndex: number) {
  document_store.setState((draft) => {
    draft.nodes.splice(nodeIndex, 1);
  });
}
