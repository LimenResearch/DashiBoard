import * as _ from "lodash";

import { createSignal } from "solid-js";

import { WindowEventListener } from "@solid-primitives/event-listener";

import { getURL, postRequest } from "./requests";

import { Loader, initLoader } from "./left-tabs/loading";
import { Filters, initFilters } from "./left-tabs/filtering";
import { Pipeline, initPipeline } from "./left-tabs/processing";

import { Spreadsheet } from "./right-tabs/spreadsheet";

import { Tabs } from "./components/tabs";
import { Visualization } from "./right-tabs/visualization";

export function App() {
    const loaderData = initLoader();
    const filtersData = initFilters();
    const pipelineData = initPipeline();

    const [result, setResult] = createSignal({summaries: [], visualization: [], report: []})

    const loadingTab = <Loader input={loaderData.input}></Loader>;
    const filteringTab = <Filters input={filtersData.input} metadata={loaderData.output()}></Filters>;
    const processingTab = <Pipeline input={pipelineData.input} metadata={loaderData.output()}></Pipeline>;

    const spec = () => ({
        filters: filtersData.output(),
        cards: pipelineData.output()
    });

    const spreadsheetTab = <Spreadsheet
        sourceMetadata={loaderData.output()}
        selectionMetadata={result().summaries}
        report={result().report}
        cards={spec().cards}></Spreadsheet>;
    const visualizationTab = <Visualization visualization={result().visualization}></Visualization>;

    const isValid = () => spec().cards.every(c => c != null);

    // TODO: control-enter to submit?
    // TODO: only update metadata if there was no error

    const onSubmit = () => {
        if (isValid()) {
            postRequest("pipeline", spec())
                .then(x => x.json())    
                .then(setResult);
        } else {
            window.alert("Invalid request, please fill out all required fields.");
        }
    };

    const onBeforeunload = e => {
        const href = _.get(document, "activeElement.href", "");
        const toSamePage = href.startsWith(getURL(""));
        if (!toSamePage) {
            e.preventDefault();
        }
    }

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Process", value: processingTab},
    ];

    const rightTabs = [
        {key: "Spreadsheet", value: spreadsheetTab},
        {key: "Visualization", value: visualizationTab},
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
