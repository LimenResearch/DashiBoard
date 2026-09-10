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

// TODO: better summary type
export type LoaderStore = {name: string, summary: any, type: string}[];

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

export function addNode(card: Card, id?: string) {
  setCards((draft) => {
    draft.nodes.push(id === undefined ? { card } : { id, card });
  });
}

export function removeNode(nodeIndex: number) {
  setCards((draft) => {
    draft.nodes.splice(nodeIndex, 1);
  });
}
