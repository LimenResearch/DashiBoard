import { createSignal, useContext } from "solid-js";

import { Button } from "../components/button";
import { FilePicker } from "../components/file-picker";
import { postRequest } from "../requests";
import { LoaderContext } from "../create";
import { createStore } from "solid-js/store";

export function initLoader() {
  const [state, setState] = createStore([]);
  return { state, setState };
}

export function Loader() {
  const { state, setState } = useContext(LoaderContext);

  const [files, setFiles] = createSignal([]);
  const [loading, setLoading] = createSignal(false);

  function loadData() {
    setLoading(true);
    postRequest("load-files", { files: files() }, state)
      .then(setState)
      .finally(setLoading(false));
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
