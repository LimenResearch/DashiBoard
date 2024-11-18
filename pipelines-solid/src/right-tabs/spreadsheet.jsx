import "@ag-grid-community/styles/ag-grid.css";
import "@ag-grid-community/styles/ag-theme-quartz.css";
import { ModuleRegistry, createGrid } from "@ag-grid-community/core";
import { InfiniteRowModelModule } from "@ag-grid-community/infinite-row-model";
import { createEffect, onMount } from "solid-js";
import { postRequest, sessionName } from "../requests";

ModuleRegistry.registerModules([InfiniteRowModelModule]);

export function Spreadsheet(props) {

    const tableNames = () => props.metadata.map(x => ({field: x.name, headerName: x.name}));

    const dataSource = () => ({
        rowCount: undefined, // behave as infinite scroll
        getRows: params => {
            const offset = params.startRow;
            const limit = params.endRow - params.startRow;
            postRequest("fetch", {session: sessionName, offset, limit})
                .then(x => x.json())
                .then(data => {
                    let lastRow = -1;
                    if (data.length <= params.endRow) {
                        lastRow = data.length;
                    }
                    params.successCallback(data.values, lastRow);
                });
        }
    });

    const gridOptions = {
        datasource: dataSource(),
        columnDefs: tableNames(),
        defaultColDef: {
            flex: 1,
            minWidth: 100,
            sortable: false,
        },
        rowBuffer: 0,
        // tell grid we want virtual row model type
        rowModelType: "infinite",
        // how big each page in our page cache will be, default is 100
        cacheBlockSize: 100,
        // how many extra blank rows to display to the user at the end of the dataset,
        // which sets the vertical scroll and then allows the grid to request viewing more rows of data.
        // default is 1, ie show 1 row.
        cacheOverflowSize: 2,
        // how many server side requests to send at a time. if user is scrolling lots, then the requests
        // are throttled down
        maxConcurrentDatasourceRequests: 1,
        // how many rows to initially show in the grid. having 1 shows a blank row, so it looks like
        // the grid is loading from the users perspective (as we have a spinner in the first col)
        infiniteInitialRowCount: 1000,
        // how many pages to store in cache. default is undefined, which allows an infinite sized cache,
        // pages are never purged. this should be set for large data to stop your browser from getting
        // full of data
        maxBlocksInCache: 10,

        // debug: true,
    };

    // setup the grid after the page has finished loading
    let gridApi, gridDiv;

    onMount(() => {
        gridApi = createGrid(gridDiv, gridOptions);
    });

    createEffect(() => {
        gridApi.updateGridOptions({columnDefs: tableNames(), datasource: dataSource()});
    });

    // TODO: avoid hard-coded height?
    return <div ref={gridDiv} style="height: 500px" class="ag-theme-quartz"></div>
}