import { createSignal } from "solid-js";

import { WindowEventListener } from "@solid-primitives/event-listener";

import { postRequest } from "./requests";

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

    const spreadsheetTab = <Spreadsheet source={loaderData.output()} selection={metadata()}></Spreadsheet>;
    const onBeforeunload = e => e.preventDefault();

    const spec = () => ({
        filters: filtersData.output(),
        cards: pipelineData.output()
    });

    const isValid = () => spec().cards.every(c => c != null);

    // TODO: control-enter to submit?
    // TODO: only update metadata if there was no error

    const onSubmit = () => {
        if (isValid()) {
            postRequest("pipeline", spec())
                .then(x => x.json())    
                .then(setMetadata);
        } else {
            window.alert("Invalid request, please fill out all required fields.");
        }
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
        <WindowEventListener onBeforeunload={onBeforeunload}></WindowEventListener>
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
