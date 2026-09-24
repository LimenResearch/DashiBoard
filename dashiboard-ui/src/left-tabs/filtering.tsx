import * as _ from "lodash";
import { Store, For, Show, reconcile } from "solid-js";

import { IntervalFilter } from "../filters/IntervalFilter";
import { ListFilter } from "../filters/ListFilter";
import { Documents } from "../components/Documents";
import {
  FILTERS_STORE,
  FiltersStore,
  LOADER_STORE,
  filtersCodec,
  droppedFilters,
  setDroppedFilters,
  type CategoricalSummary,
  type NumericalSummary,
} from "../stores";

function nonNullEntries(obj: Object) {
  return _.entries(obj).filter(([k, v]) => v != null);
}

export function getFilters(state: Store<FiltersStore>) {
  const [numerical, categorical] = [state.numerical, state.categorical].map(
    nonNullEntries,
  );
  const intervals: Array<any> = numerical.map(([colname, interval]) => ({
    type: "interval",
    colname,
    interval,
  }));
  const lists: Array<any> = categorical.map(([colname, list]) => ({
    type: "list",
    colname,
    list: Array.from(list),
  }));
  return intervals.concat(lists);
}

export function Filters() {
  
  const [state, setState] = FILTERS_STORE;
  const [metadata] = LOADER_STORE;

  // Narrowing predicates rather than a bare filter: each list feeds a component that accepts one
  // summary shape, and without the guard `<For>` cannot check that it is handed the right one.
  const numerical = () =>
    metadata.filter((entry): entry is NumericalSummary => entry.type === "numerical");
  const categorical = () =>
    metadata.filter((entry): entry is CategoricalSummary => entry.type === "categorical");

  return (
    <div>
      {/* What the last load dropped: a filter on a column this table does not have cannot apply.
          Said once, here, rather than kept for the author to remove by hand. */}
      <Show when={droppedFilters().length > 0}>
        <div
          data-dropped-filters
          class="mb-3 flex items-start gap-2 rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground"
        >
          <span class="min-w-0 flex-1">
            Filters removed — not in the loaded table:{" "}
            <span class="font-mono">{droppedFilters().join(", ")}</span>
          </span>
          <button
            type="button"
            aria-label="dismiss"
            onClick={() => setDroppedFilters([])}
            class="grid h-4 w-4 shrink-0 place-items-center rounded-sm text-muted-foreground hover:bg-secondary hover:text-foreground"
          >
            ×
          </button>
        </div>
      </Show>
      <div class="flex flex-row gap-2 pb-4">
        <div class="basis-1/2">
          <For each={numerical()}>{IntervalFilter}</For>
        </div>
        <div class="basis-1/2">
          <For each={categorical()}>{ListFilter}</For>
        </div>
      </div>
      {/*
        Through the codec both ways. The store holds `Interval`s and `Set`s, which are not JSON:
        a `Set` stringifies to `{}`, so the file `Download filters` used to write could not be
        loaded back, and an uploaded file reached the store as plain objects and arrays. Loading
        replaces the store wholesale (`reconcile`) rather than merging — a merge would leave
        filters the file does not mention still applied.
      */}
      <Documents
        kind="filters"
        document={() => filtersCodec.encode(state)}
        onLoad={(document) => {
          setState(reconcile(filtersCodec.decode(document)));
          return [];
        }}
      />
    </div>
  );
}
