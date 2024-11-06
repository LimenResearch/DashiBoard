import { createResource, createSignal } from "solid-js";
import { join } from 'path-browserify'

import { PathPicker } from "./left-tabs/loading";
import { Filters } from "./left-tabs/filtering";
import { Tabs } from "./components/tabs";

function postRequest(url, body) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch(url, {
        method: "POST",
        body: JSON.stringify(body),
        headers: myHeaders,
    });

    return response.then(x => x.json());
}

const sessionName = "user-experiment";

function fetchTableMetadata(paths) {
    const url = "http://127.0.0.1:8080/load";
    const experiment = {files: paths.map(x => join(...x)), name: sessionName}
    const body = {experiment};
    return postRequest(url, body);
}

function filterData(paths, store) {
    const url = "http://127.0.0.1:8080/filter";
    const experiment = {files: paths.map(x => join(...x)), name: sessionName};

    const [numerical, categorical] = [store.numerical, store.categorical].map(nonNullEntries);
    const intervals = numerical.map(([colname, interval]) => ({type: "interval", colname, interval}));
    const lists = categorical.map(([colname, list]) => ({type: "list", colname, list: Array.from(list)}));
    const filters = intervals.concat(lists);

    const body = {experiment, filters};
    postRequest(url, body);
}

function nonNullEntries(obj) {
    const res = [];
    for (const k in obj) {
        const v = obj[k];
        (v == null) || res.push([k, v]);
    }
    return res
}

// TODO: ensure reloading upon failure if button is clicked again
// TODO: disable button during loading
export function App() {
    const [paths, updatePaths] = createSignal(null);
    const [metadata] = createResource(paths, fetchTableMetadata);

    const loadingTab = <PathPicker directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onValue={updatePaths}>
    </PathPicker>;

    const filteringTab = <Filters metadata={metadata() || []} onValue={store => filterData(paths(), store)}></Filters>;

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Preprocess", value: "TODO"},
    ];

    return <div class="min-w-screen min-h-screen bg-gray-100">
        <Tabs>{leftTabs}</Tabs>
    </div>;
}
