import { Combobox } from "./Combobox";
import { Button } from "./Button";

import { createSignal } from "solid-js";
import { postRequest } from "../requests";
import * as _ from "lodash";

type FilePickerProps = {
  required?: boolean;
  onChange?: (value: string | string[]) => void;
  multiple?: boolean;
};

export function FilePicker(props: FilePickerProps) {
  // Asked once at mount, and again on the button. A memo over the promise asked exactly once:
  // if the server was still starting, `postRequest` answered `null`, the list stayed empty and
  // nothing asked again — a reload during the same boot gave the same nothing (owner,
  // 2026-09-18). The server walks the directory on every request, so asking is all it takes.
  const [files, setFiles] = createSignal<string[]>([]);
  // `true` from the start rather than set on the way in: Solid 2 refuses a signal write during a
  // component's own setup (`REACTIVE_WRITE_IN_OWNED_SCOPE`), and the first request goes out
  // from exactly there. The replies write from a microtask, which is fine.
  const [asking, setAsking] = createSignal(true);
  const request = () =>
    postRequest("get-acceptable-paths", {}, null)
      .then((answer: unknown) => setFiles(Array.isArray(answer) ? (answer as string[]) : []))
      .finally(() => setAsking(false));
  void request();
  function ask() {
    setAsking(true);
    void request();
  }
  const options = () => files().map((x: string) => ({ label: x, value: x }));
  const selectClass = "text-primary font-semibold py-2 w-full text-left";
  const id = _.uniqueId("load_");
  return (
    <>
      <label for={id} class={selectClass}>
        Choose files
      </label>
      <div class="flex items-start gap-2">
        <div class="min-w-0 grow">
          <Combobox
            id={id}
            required={props.required}
            onChange={props.onChange}
            multiple={props.multiple}
            options={options()}
          ></Combobox>
        </div>
        <Button
          disabled={asking()}
          title="ask the server for the files again"
          label="refresh the file list"
          onClick={ask}
        >
          ↻
        </Button>
      </div>
    </>
  );
}
