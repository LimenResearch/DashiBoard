import { createSignal, reconcile } from "solid-js";

import { Button } from "../components/Button";
import { FilePicker } from "../components/FilePicker";
import { postRequest } from "../requests";
import { LOADER_STORE, type LoaderStore } from "../stores";

export function Loader() {
  const [state, setState] = LOADER_STORE;

  const [files, setFiles] = createSignal([]);
  const [loading, setLoading] = createSignal(false);

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
    </div>
  );
}
