import { createMemo, createSignal, reconcile, Show } from "solid-js";

import { Button } from "../components/Button";
import { FilePicker } from "../components/FilePicker";
import { TableView } from "../components/TableView";
import { postRequest } from "../requests";
import {
  LOADER_JSON, LOADER_STORE, pruneFilters, pruneReferences, setDroppedReferences, type LoaderStore,
} from "../stores";

export function Loader() {
  const [state, setState] = LOADER_STORE;

  const [files, setFiles] = createSignal([]);
  const [loading, setLoading] = createSignal(false);

  /** How many loads have landed. See `revision`. */
  const [loads, setLoads] = createSignal(0);
  /**
   * Which source the preview is showing — the table's `revision`.
   *
   * Two things move it. The store's own serialisation, because the store *is* the loaded source:
   * whoever writes it has replaced the rows (`LOADER_JSON` is the string persistence already
   * builds, so this costs one comparison). And every load that lands, because the summaries alone
   * cannot tell two tables apart: a summary is a column's extrema or its distinct values, so the
   * same rows in another order — or yesterday's export and today's — summarise identically, and
   * the grid kept showing the first file's rows after the second had been loaded (measured
   * 2026-09-21; seen in a browser with `same-summary-A/B.parquet`).
   */
  const revision = createMemo((previous: number | undefined) => {
    void LOADER_JSON();
    void loads();
    return (previous ?? 0) + 1;
  });

  function loadData() {
    setLoading(true);
    // A Solid 2 store setter takes a *function*, so `.then(setState)` handed it the response array
    // and nothing was stored — every column vocabulary downstream stayed empty with no error.
    // `reconcile` is the idiomatic wholesale replace.
    postRequest("load-files", { files: files() }, [])
      .then((summaries: LoaderStore) => {
        const next = summaries ?? [];
        setState(reconcile(next));
        // Filters are part of the document, but one on a column this table lacks cannot apply:
        // dropped, and announced in the Filter tab. See `pruneFilters`.
        pruneFilters(next);
        // The same for what cards and groups refer to; said in the Process tab.
        setDroppedReferences(pruneReferences(next.map((summary) => summary.name)));
        setLoads((n) => n + 1);
      })
      .finally(() => setLoading(false));
  }

  return (
    <div>
      <div class="p-3">
        <FilePicker kind="table" required multiple onChange={setFiles}></FilePicker>
      </div>
      <div class="p-3">
        <Button
          disabled={loading() || files() == null || files().length == 0}
          onClick={loadData}
        >
          Load
        </Button>
      </div>

      {/*
        What was loaded, scrollable. The grid pages through `fetch-data` rather than holding the
        table, so this stays usable on a source far larger than the browser — which is the point
        of previewing it here rather than trusting the column list.

        `processed={false}` reads the source; the pipeline's output is a different pane (C4).
      */}
      <Show when={state.length > 0}>
        <div class="p-3">
          <p class="mb-1.5 text-detail tracking-wider text-muted-foreground uppercase">
            {state.length} columns
          </p>
          <TableView processed={false} revision={revision()} metadata={state} class="h-80" />
        </div>
      </Show>
    </div>
  );
}
