import { PathPicker } from "./components/path-picker";
import { Tabs } from "./components/tabs";

function initializeQueryParams() {
    return {
        paths: [],
        format: "",
        listFilters: [],
        intervalFilters: [],
        preprocessors: []
    };
}

function postRequest(body) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch("http://127.0.0.1:8080/load", {
        method: "POST",
        body: JSON.stringify(body),
        headers: myHeaders,
    });

    response.then(x => x.json()).then(console.log);
}

function getExt(path) {
    return path.at(-1).split('.').at(-1);
}

export function App() {
    const queryParams = initializeQueryParams();
    const setPaths = paths => {
        queryParams.paths = paths;
        queryParams.format = getExt(paths[0]);
        console.log(queryParams);
    };
    const loadData = () => postRequest({paths: queryParams.paths, format: queryParams.format});
    const onValue = paths => {
        setPaths(paths);
        loadData();
    }

    const loadingTab = <PathPicker directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onValue={onValue}>
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
