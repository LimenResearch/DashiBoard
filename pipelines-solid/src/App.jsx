import { PathPicker } from "./components/path-picker";
import { Tabs } from "./components/tabs";

function initializeQueryParams() {
    return {
        paths: [],
        listFilters: [],
        intervalFilters: [],
        preprocessors: []
    };
}

export function App() {
    const queryParams = initializeQueryParams();
    const setPaths = paths => {
        queryParams.paths = paths;
        console.log(queryParams);
    };

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
