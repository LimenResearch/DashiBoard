import { createMemo, createSignal, reconcile, Show } from "solid-js";

import { Button } from "../components/Button";
import { FilePicker } from "../components/FilePicker";
import { TableView } from "../components/TableView";
import { postRequest } from "../requests";
import { LOADER_JSON, LOADER_STORE, type LoaderStore } from "../stores";

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
    // A Solid 2 store setter takes a *function*, so `.then(setState)` handed it the response array
    // and nothing was stored — every column vocabulary downstream stayed empty with no error.
    // `reconcile` is the idiomatic wholesale replace.
    postRequest("load-files", { files: files() }, [])
      .then((summaries: LoaderStore) => setState(reconcile(summaries ?? [])))
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
