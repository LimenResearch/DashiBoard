import { createSignal } from "solid-js";

import { Button } from "../components/Button";
import { FilePicker } from "../components/FilePicker";
import { postRequest } from "../requests";
import { LOADER_STORE } from "../stores";

export function Loader() {
  const [state, setState] = LOADER_STORE;

  const [files, setFiles] = createSignal([]);
  const [loading, setLoading] = createSignal(false);

  function loadData() {
    setLoading(true);
    postRequest("load-files", { files: files() }, state)
      .then(setState)
      .finally(() => setLoading(false));
  }

  return (
    <div>
      <div class="p-4">
        <FilePicker required multiple onChange={setFiles}></FilePicker>
      </div>
      <div class="p-4">
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
