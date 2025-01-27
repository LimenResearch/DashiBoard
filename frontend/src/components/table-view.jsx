import { ModuleRegistry, createGrid } from "@ag-grid-community/core";
import { InfiniteRowModelModule } from "@ag-grid-community/infinite-row-model";
import { createEffect, onMount } from "solid-js";
import { postRequest } from "../requests";

ModuleRegistry.registerModules([InfiniteRowModelModule]);

function formatter(val, eltype) {
    if (val == null) {
        return null;
    }
    switch (eltype) {
        case "float":
            return val.toPrecision(5);
        default:
            return val;
    }
}

export function TableView(props) {

    const dataSource = columnDefs => {
        if (columnDefs.length == 0) {
            return { rowCount: 0, getRows: params => params.successCallback([], 0) };
        } else {
            return {
                rowCount: undefined, // behave as infinite scroll
                getRows: params => {
                    const offset = params.startRow;
                    const limit = params.endRow - params.startRow;
                    postRequest("fetch", { offset, limit, processed: props.processed })
                        .then(x => x.json())
                        .then(data => {
                            let lastRow = -1;
                            if (data.length <= params.endRow) {
                                lastRow = data.length;
                            }
                            params.successCallback(data.values, lastRow);
                        });
                }
            };
        }
    };

    const options = () => {
        const columnDefs = props.metadata.map(x => ({
            field: x.name,
            headerName: x.name,
            valueFormatter: params => formatter(params.value, x.eltype),
        }));
        const datasource = dataSource(columnDefs);
        const suppressFieldDotNotation = true;
        return {datasource, columnDefs, suppressFieldDotNotation};
    }

    const gridOptions = {
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

    createEffect(() => gridApi.updateGridOptions(options()));

    // TODO: avoid hard-coded height?
    return <div ref={gridDiv} style="height: 500px" class="ag-theme-quartz"></div>
}