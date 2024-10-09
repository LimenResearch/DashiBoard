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

// TODO: ensure reloading upon failure if button is clicked again
export function App() {
    const [paths, setPaths] = createSignal(null);

    const [metadata] = createResource(paths, fetchTableMetadata);

    const loadingTab = <PathPicker directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onValue={setPaths}>
    </PathPicker>;

    const filteringTab = <Filters metadata={metadata() || []}></Filters>;

    const tabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Preprocess", value: "TODO"},
    ];

    return <div class="min-w-screen min-h-screen bg-gray-100">
        <Tabs>{tabs}</Tabs>
    </div>;
}
