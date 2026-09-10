import * as _ from "lodash";
import { Store, For } from "solid-js";

import { IntervalFilter } from "../filters/IntervalFilter";
import { ListFilter } from "../filters/ListFilter";
import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { FILTERS_STORE, FiltersStore, LOADER_STORE } from "../stores";

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

  const numerical = () => metadata.filter((entry) => entry.type == "numerical");
  const categorical = () =>
    metadata.filter((entry) => entry.type == "categorical");

  return (
    <div>
      <div class="flex flex-row gap-2 pb-4">
        <div class="basis-1/2">
          <For each={numerical()}>{IntervalFilter}</For>
        </div>
        <div class="basis-1/2">
          <For each={categorical()}>{ListFilter}</For>
        </div>
      </div>
      <DownloadJSONButton data={state} name="filters.json">
        Download filters
      </DownloadJSONButton>
      <UploadJSONButton def={state} onChange={setState}>
        Upload filters
      </UploadJSONButton>
    </div>
  );
}
