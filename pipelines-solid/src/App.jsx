import { postRequest, sessionName } from "./requests";
import "@thisbeyond/solid-select/style.css";

import { Loader, initLoader } from "./left-tabs/loading";
import { Filters, initFilters } from "./left-tabs/filtering";
import { Pipeline, initPipeline } from "./left-tabs/processing";
import { Tabs } from "./components/tabs";

export function App() {
    const loaderData = initLoader();
    const filtersData = initFilters();
    const pipelineData = initPipeline();

    const loadingTab = <Loader input={loaderData.input}></Loader>;
    const filteringTab = <Filters input={filtersData.input} metadata={loaderData.output()}></Filters>;
    const processingTab = <Pipeline input={pipelineData.input} metadata={loaderData.output()}></Pipeline>;

    const spec = () => ({
        session: sessionName,
        filters: filtersData.output(),
        cards: pipelineData.output()
    });

    const onSubmit = () => {
        postRequest("pipeline", spec())
    };

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Process", value: processingTab},
    ];

    const rightTabs = [
        {key: "Spreadsheet", value: "TODO"},
        {key: "Chart", value: "TODO"},
        {key: "Pipeline", value: "TODO"},
    ];

    return <div class="min-w-screen min-h-screen bg-gray-100">
        <div class="grid grid-cols-2 gap-8">
            <div>
                <Tabs submit="Submit" onSubmit={onSubmit}>{leftTabs}</Tabs>
            </div>
            <div>
                <Tabs submit="Submit">{rightTabs}</Tabs>
            </div>
        </div>
    </div>;
}
