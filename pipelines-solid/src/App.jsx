import { createEffect, createResource, createSignal } from "solid-js";
import { PathPicker } from "./left-tabs/loading";
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

export function App() {
    const [paths, setPaths] = createSignal(null);

    const [metadata] = createResource(paths, fetchTableMetadata);

    // Effect for debugging
    createEffect(() => console.log(metadata()));

    const loadingTab = <PathPicker directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onValue={setPaths}>
    </PathPicker>;

    const tabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: "TODO"},
        {key: "Preprocess", value: "TODO"},
    ];

    return <div class="w-screen min-h-screen bg-gray-100">
        <Tabs>{tabs}</Tabs>
    </div>;
}
