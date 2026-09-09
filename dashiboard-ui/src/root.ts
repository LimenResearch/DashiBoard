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
