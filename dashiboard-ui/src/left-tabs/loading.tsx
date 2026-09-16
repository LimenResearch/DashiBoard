import { createMemo, createSignal, reconcile, Show } from "solid-js";

import { Button } from "../components/Button";
import { FilePicker } from "../components/FilePicker";
import { TableView } from "../components/TableView";
import { postRequest } from "../requests";
import { LOADER_JSON, LOADER_STORE, FILTERS_STORE, type LoaderStore } from "../stores";

export function Loader() {
  const [state, setState] = LOADER_STORE;

  const [files, setFiles] = createSignal([]);
  const [loading, setLoading] = createSignal(false);

  /**
   * Which source the preview is showing — the table's `revision`.
   *
   * Counted off the store's own serialisation rather than bumped inside `loadData`, because the
   * store *is* the loaded source: whoever writes it has replaced the rows, and a second file with
   * the very same column names is still a different table. `LOADER_JSON` is the string
   * persistence already builds, so this costs one comparison and no second walk of the store.
   */
  const revision = createMemo((previous: number | undefined) => {
    void LOADER_JSON();
    return (previous ?? 0) + 1;
  });

  function loadData() {
    setLoading(true);
    // Capture the before state (column names) at the top of loadData, synchronously, not inside
    // the promise callback — Solid 2 does not warn for reads in promise callbacks, but we compute
    // `before` here rather than inside `.then` to be safe and clear.
    const before = state.map((s) => s.name).sort().join(" ");

    // A Solid 2 store setter takes a *function*, so `.then(setState)` handed it the response array
    // and nothing was stored — every column vocabulary downstream stayed empty with no error.
    // `reconcile` is the idiomatic wholesale replace.
    postRequest("load-files", { files: files() }, [])
      .then((summaries: LoaderStore) => {
        const next = summaries ?? [];
        // Filters are authored against one table's columns. A table with different columns
        // makes them meaningless — a list filter on `cbwd` over a table with no `cbwd` failed
        // the run (measured 2026-09-16) — so a changed column set clears them; the same names
        // (the CSV and the parquet of one dataset) keep them.
        const after = next.map((s) => s.name).sort().join(" ");
        if (before !== after) {
          const [, setFilters] = FILTERS_STORE;
          setFilters(reconcile({ numerical: {}, categorical: {} }));
        }
        setState(reconcile(next));
      })
      .finally(() => setLoading(false));
  }

  return (
    <div>
      <div class="p-3">
        <FilePicker required multiple onChange={setFiles}></FilePicker>
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
