import { createRoot, createStore, Store, StoreSetter } from "solid-js";

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

type CardsStore = {
  cards: { [key: string]: any }[];
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

export const cards_store = createRoot((dispose) => {
  const [state, setState] = createStore<CardsStore>({
    cards: [],
  } as CardsStore);
  return { state, setState, dispose };
});
