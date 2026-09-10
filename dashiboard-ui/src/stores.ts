import { createStore } from "solid-js";

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

export type CardsStore = {
  cards: { [key: string]: any }[];
};

export const CARDS_STORE = createStore<CardsStore>({
  cards: [],
} as CardsStore);
