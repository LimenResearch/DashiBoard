import { PathPicker } from "./components/path-picker";

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

    return <PathPicker directoryMessage="Enable folder"
        fileMessage="Choose files" confirmationMessage="Load" onValue={setPaths}>
    </PathPicker>;
}