import * as _ from "lodash";

import { createSignal } from "solid-js";

import { WindowEventListener } from "@solid-primitives/event-listener";

import { getURL, postRequest } from "./requests";

import { Loader, initLoader } from "./left-tabs/loading";
import { Filters, getFilters, initFilters } from "./left-tabs/filtering";
import { Cards, getCards, initCards } from "./left-tabs/processing";

import { Spreadsheet } from "./right-tabs/spreadsheet";
import { Visualization } from "./right-tabs/visualization";
import { Graph } from "./right-tabs/graph";

import { Tabs } from "./components/tabs";
import { FiltersContext, LoaderContext, CardsContext } from "./create";

export function App() {
  const LoaderData = initLoader();
  const metadata = LoaderData.state;

  const filtersData = initFilters(metadata);
  const cardsData = initCards(metadata);

  const [result, setResult] = createSignal({
    summaries: [],
    visualization: [],
    report: [],
  });

  const loadingTab = (
    <LoaderContext.Provider value={LoaderData}>
      <Loader></Loader>
    </LoaderContext.Provider>
  );
  const filteringTab = (
    <FiltersContext.Provider value={filtersData}>
      <Filters></Filters>
    </FiltersContext.Provider>
  );
  const processingTab = (
    <CardsContext.Provider value={cardsData}>
      <Cards></Cards>
    </CardsContext.Provider>
  );

  const spec = () => ({
    filters: getFilters(filtersData.state),
    cards: getCards(cardsData.state),
  });

  const spreadsheetTab = (
    <Spreadsheet
      sourceMetadata={metadata}
      selectionMetadata={result().summaries}
      report={result().report}
      cards={spec().cards}
    ></Spreadsheet>
  );
  const visualizationTab = (
    <Visualization visualization={result().visualization}></Visualization>
  );
  const graphTab = <Graph graph={result().graph}></Graph>;

  const isValid = () => spec().cards.every((c) => c != null);

  // TODO: control-enter to submit?
  // TODO: only update metadata if there was no error

  const onSubmit = () => {
    if (isValid()) {
      postRequest("evaluate-pipeline", spec(), result()).then(setResult);
    } else {
      window.alert("Invalid request, please fill out all required fields.");
    }
  };

  const onBeforeunload = (e) => {
    const href = _.get(document, "activeElement.href", "");
    const toSamePage = href.startsWith(getURL(""));
    if (!toSamePage) {
      e.preventDefault();
    }
  };

  const leftTabs = [
    { key: "Load", value: loadingTab },
    { key: "Filter", value: filteringTab },
    { key: "Process", value: processingTab },
  ];

  const rightTabs = [
    { key: "Spreadsheet", value: spreadsheetTab },
    { key: "Visualization", value: visualizationTab },
    { key: "Graph", value: graphTab },
  ];

  const outerClass = `bg-gray-100 w-full max-h-screen min-h-screen
        overflow-y-auto scrollbar-gutter-stable`;

  return (
    <div class={outerClass}>
      <WindowEventListener
        onBeforeunload={onBeforeunload}
      ></WindowEventListener>
      <div class="max-w-full grid grid-cols-5 gap-8 mr-4">
        <div class="col-span-2">
          <Tabs submit="Submit" onSubmit={onSubmit}>
            {leftTabs}
          </Tabs>
        </div>
        <div class="col-span-3">
          <Tabs>{rightTabs}</Tabs>
        </div>
      </div>
    </div>
  );
}
