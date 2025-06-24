import * as _ from "lodash"
import { useContext } from "solid-js";

import { IntervalFilter } from "../filters/interval-filter";
import { ListFilter } from "../filters/list-filter";
import { DownloadJSON, UploadJSON } from "../components/json";
import { FiltersContext } from "../create";
import { createStore } from "solid-js/store";

export function initFilters(metadata) {
    const [state, setState] = createStore({numerical: {}, categorical: {}});
    return {state, setState, metadata};
}

function nonNullEntries(obj) {
    return _.entries(obj).filter(([k, v]) => v != null);
}

export function getFilters(state) {
    const [numerical, categorical] = [state.numerical, state.categorical].map(nonNullEntries);
    const intervals = numerical.map(([colname, interval]) => ({type: "interval", colname, interval}));
    const lists = categorical.map(([colname, list]) => ({type: "list", colname, list: Array.from(list)}));
    return intervals.concat(lists);
}

export function Filters() {
    const {state, setState, metadata} = useContext(FiltersContext);

    const numerical = () => metadata.filter(entry => entry.type == "numerical");
    const categorical = () => metadata.filter(entry => entry.type == "categorical");

    return <div>
        <div class="flex flex-row gap-4 pb-4">
            <div class="basis-1/2"><For each={numerical()}>{IntervalFilter}</For></div>
            <div class="basis-1/2"><For each={categorical()}>{ListFilter}</For></div>
        </div>
        <DownloadJSON data={state} name="filters.json">
            Download filters
        </DownloadJSON>
        <UploadJSON def={state} onChange={setState}>
            Upload filters
        </UploadJSON>
    </div>;
}
