import { createResource, createSignal } from "solid-js";

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

function getExt(path) {
    return path.at(-1).split('.').at(-1);
}

function fetchTableMetadata(paths) {
    const url = "http://127.0.0.1:8080/load";
    const format = getExt(paths[0]);
    const body = {paths, format};
    return postRequest(url, body);
}

function fetchFilteredData(filters) {
    const url = "http://127.0.0.1:8080/filter";
    console.log(filters);
    return null;
}

// TODO: ensure reloading upon failure if button is clicked again
// TODO: disable button during loading
export function App() {
    const [paths, updatePaths] = createSignal(null);

    const [filters, setFilters] = createSignal({intervals: [], lists: []});

    const updateFilters = (store) => {
        const {numerical, categorical} = store;
        const fs = {intervals: [], lists: []};
        for (const colname in numerical) {
            const interval = numerical[colname];
            if (interval != null) {
                fs.intervals.push({colname, interval});
            }
        }
        for (const colname in categorical) {
            const obj = categorical[colname];
            if (obj != null) {
                const list = Object.keys(obj).filter(x => x);
                fs.lists.push({colname, list});
            }
        }
        setFilters(fs);
    }

    const [metadata] = createResource(paths, fetchTableMetadata);
    const [filteredTable] = createResource(filters, fetchFilteredData);

    const loadingTab = <PathPicker directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onValue={updatePaths}>
    </PathPicker>;

    const filteringTab = <Filters metadata={metadata() || []} onValue={updateFilters}></Filters>;

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Preprocess", value: "TODO"},
    ];

    return <div class="min-w-screen min-h-screen bg-gray-100">
        <Tabs>{leftTabs}</Tabs>
    </div>;
}
