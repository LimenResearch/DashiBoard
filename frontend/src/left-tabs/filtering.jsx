import * as _ from "lodash"
import { createStore } from "solid-js/store";

import { IntervalFilter } from "../filters/interval-filter";
import { ListFilter } from "../filters/list-filter";
import { DownloadJSON, UploadJSON } from "../components/json";

function nonNullEntries(obj) {
    return _.entries(obj).filter(([k, v]) => v != null);
}

function getFilters(store) {
    const [numerical, categorical] = [store.numerical, store.categorical].map(nonNullEntries);
    const intervals = numerical.map(([colname, interval]) => ({type: "interval", colname, interval}));
    const lists = categorical.map(([colname, list]) => ({type: "list", colname, list: Array.from(list)}));
    return intervals.concat(lists);
}

export function initFilters() {
    const [store, setStore] = createStore({numerical: {}, categorical: {}});
    const filters = () => getFilters(store);
    return {input: [store, setStore], output: filters};
}

export function Filters(props) {
    const [store, setStore] = props.input;

    const numerical = () => props.metadata
        .filter(entry => entry.type == "numerical")
        .map(entry => _.assign({store, setStore}, entry));

    const categorical = () => props.metadata
        .filter(entry => entry.type == "categorical")
        .map(entry => _.assign({store, setStore}, entry));

    return <div>
        <div class="flex flex-row gap-4 pb-4">
            <div class="basis-1/2"><For each={numerical()}>{IntervalFilter}</For></div>
            <div class="basis-1/2"><For each={categorical()}>{ListFilter}</For></div>
        </div>
        <DownloadJSON data={store} name="filters.json">
            Download filters
        </DownloadJSON>
        <UploadJSON def={store} onChange={setStore}>
            Upload filters
        </UploadJSON>
    </div>;
}
