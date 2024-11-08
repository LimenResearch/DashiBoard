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
    const processingTab = <Pipeline input={pipelineData.input}></Pipeline>;

    const leftTabs = [
        {key: "Load", value: loadingTab},
        {key: "Filter", value: filteringTab},
        {key: "Process", value: processingTab},
    ];

    return <div class="min-w-screen min-h-screen bg-gray-100">
        <Tabs>{leftTabs}</Tabs>
    </div>;
}
