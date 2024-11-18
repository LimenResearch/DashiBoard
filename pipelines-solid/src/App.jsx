import "@thisbeyond/solid-select/style.css";
import { createSignal } from "solid-js";

import { postRequest, sessionName } from "./requests";

import { Loader, initLoader } from "./left-tabs/loading";
import { Filters, initFilters } from "./left-tabs/filtering";
import { Pipeline, initPipeline } from "./left-tabs/processing";

import { Spreadsheet } from "./right-tabs/spreadsheet";

import { Tabs } from "./components/tabs";

export function App() {
    const loaderData = initLoader();
    const filtersData = initFilters();
    const pipelineData = initPipeline();

    const [metadata, setMetadata] = createSignal([]);

    const loadingTab = <Loader input={loaderData.input}></Loader>;
    const filteringTab = <Filters input={filtersData.input} metadata={loaderData.output()}></Filters>;
    const processingTab = <Pipeline input={pipelineData.input} metadata={loaderData.output()}></Pipeline>;

    const spreadsheetTab = <Spreadsheet metadata={metadata()}></Spreadsheet>;

    const spec = () => ({
        session: sessionName,
        filters: filtersData.output(),
        cards: pipelineData.output()
    });

    // TODO: control-enter to submit?

    const onSubmit = () => {
        postRequest("pipeline", spec())
            .then(x => x.json())    
            .then(setMetadata);
    };

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Process", value: processingTab},
    ];

    const rightTabs = [
        {key: "Spreadsheet", value: spreadsheetTab},
        {key: "Chart", value: "TODO"},
        {key: "Pipeline", value: "TODO"},
    ];

    const outerClass = `bg-gray-100 w-full max-h-screen min-h-screen
        overflow-y-auto scrollbar-gutter-stable`;

    return <div class={outerClass}>
        <div class="max-w-full grid grid-cols-5 gap-8 mr-4">
            <div class="col-span-2">
                <Tabs submit="Submit" onSubmit={onSubmit}>{leftTabs}</Tabs>
            </div>
            <div class="col-span-3">
                <Tabs>{rightTabs}</Tabs>
            </div>
        </div>
    </div>;
}
