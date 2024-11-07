import { createSignal } from "solid-js";

import { PathPicker, initPathPicker } from "./left-tabs/loading";
import { Filters, initFilters } from "./left-tabs/filtering";
import { Tabs } from "./components/tabs";

function postRequest(page, body) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch("http://127.0.0.1:8080/" + page, {
        method: "POST",
        body: JSON.stringify(body),
        headers: myHeaders,
    });

    return response;
}

const sessionName = "user-experiment";

export function App() {
    const [metadata, setMetadata] = createSignal([]);
    const pathPickerData = initPathPicker();
    const filtersData = initFilters();

    const spec = () => {
        return {
            experiment: {name: sessionName, files: pathPickerData.output()},
            filters: filtersData.output(),
        };
    };

    function loadData() {
        postRequest("load", spec()).then(x => x.json()).then(setMetadata);
    }

    const loadingTab = <PathPicker input={pathPickerData.input} directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onLoad={loadData}>
    </PathPicker>;

    const filteringTab = <Filters input={filtersData.input} metadata={metadata()}></Filters>;

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Preprocess", value: "TODO"},
    ];

    return <div class="min-w-screen min-h-screen bg-gray-100">
        <Tabs>{leftTabs}</Tabs>
    </div>;
}
