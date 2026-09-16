import { ModuleRegistry, createGrid, GridApi, RowModelType } from "@ag-grid-community/core";
import { InfiniteRowModelModule } from "@ag-grid-community/infinite-row-model";
import { createEffect, createMemo, onSettled } from "solid-js";

// Structural first, theme second — and both were missing. `ag-theme-quartz` was on the element
// while `@ag-grid-community/styles` was not installed at all, so the class named a theme that did
// not exist. Imported here rather than in App.css so the grid's stylesheets travel with the one
// component that needs them, and drop out of the bundle when it is not used.
import "@ag-grid-community/styles/ag-grid.css";
import "@ag-grid-community/styles/ag-theme-quartz.css";

import { postRequest } from "../requests";

// Colours and density come from the `.ag-theme-quartz` block in App.css, which maps ag-grid's
// `--ag-*` variables onto our tokens. Nothing here should set a colour.

ModuleRegistry.registerModules([InfiniteRowModelModule]);

type GetRowsParams = {
  startRow: number;
  endRow: number;
  filterModel: unknown;
  sortModel: unknown;
  successCallback: (rows: unknown[], lastRow: number) => void;
  failCallback: () => void;
};

/** What `POST /fetch-data` answers: a page of rows, plus the table's total row count. */
type FetchedRows = { values: unknown[]; length: number };

// ag-grid renders whatever this returns, and its own type says string — which the previous
// `any` let slip: a null came back for an empty cell and a raw value for everything else.
function formatter(val: unknown, eltype: string): string {
  if (val == null) return "";
  // Only floats need shortening; everything else is shown as the server sent it.
  return eltype === "float" && typeof val === "number" ? val.toPrecision(5) : String(val);
}

type Column = { name: string; eltype: string };

type TableViewProps = {
  /** Read the pipeline's output rather than the loaded source. */
  processed: boolean;
  /** Readonly, because a store proxy is — and this only ever reads it. */
  metadata: readonly Column[];
  /** The grid needs a definite height; it cannot size to its content. */
  class?: string;
};

export function TableView(props: TableViewProps) {
  const dataSource = (processed: boolean) => {
    return {
      rowCount: undefined, // behave as infinite scroll
      getRows: (params: GetRowsParams) => {
        const { startRow, endRow, filterModel, sortModel } = params;
        const offset = startRow;
        const limit = endRow - startRow;
        void postRequest(
          "fetch-data",
          {
            offset,
            limit,
            filterModel,
            sortModel,
            processed,
          },
          null,
        ).then((data: FetchedRows | null) => {
          if (!data) {
            params.failCallback();
            return;
          }
          // `data.length` is the table's total row count, not `values.length` — the route
          // answers `{"values": …, "length": nrows}`. Handing it over with every block tells
          // the grid where the table ends from the first page on, so it never asks past it.
          // Not testable in jsdom (no layout, so the grid never pages); the access log is the
          // evidence.
          params.successCallback(data.values, data.length);
        });
      },
    };
  };

  // Two effects, not one. The datasource is what the infinite row model pages through, and
  // handing the grid a *new* one resets its block cache and refetches from row 0 — so it is
  // built once per `processed` and never rebuilt for a column change. Columns are the cheap
  // half and update on their own.
  const datasource = createMemo(() => dataSource(props.processed));
  const columnDefs = createMemo(() =>
    props.metadata.map((x: Column) => ({
      field: x.name,
      headerName: x.name,
      valueFormatter: (params: { value: unknown }) => formatter(params.value, x.eltype),
    })),
  );

  const gridOptions = {
    defaultColDef: {
      flex: 1,
      minWidth: 100,
    },
    rowBuffer: 0,
    // tell grid we want virtual row model type
    rowModelType: "infinite" as RowModelType,
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
  let gridApi: GridApi | undefined;
  let gridDiv!: HTMLDivElement;

  onSettled(() => {
    gridApi = createGrid(gridDiv, gridOptions);
  });

  createEffect(datasource, (next) => gridApi?.updateGridOptions({ datasource: next }));
  createEffect(columnDefs, (next) =>
    gridApi?.updateGridOptions({ columnDefs: next, suppressFieldDotNotation: true }),
  );

  return <div ref={gridDiv} class={["ag-theme-quartz", props.class ?? "h-96"]} />;
}
