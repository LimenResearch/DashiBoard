import { Combobox } from "./Combobox";
import { Button } from "./Button";

import { createSignal, untrack } from "solid-js";
import { postRequest } from "../requests";
import * as _ from "lodash";

/** What `list-files` says a file is. A JSON is told from a table by content, server-side. */
export type FileKind = "table" | "cards" | "filters";
type Listed = { path: string; kind: FileKind };

type FilePickerProps = {
  /** Which files of the data directory this picker offers. */
  kind: FileKind;
  required?: boolean;
  onChange?: (value: string | string[]) => void;
  multiple?: boolean;
  /** Defaults to "Choose files", which is what the Load tab says. */
  label?: string;
  /** Receives the function the refresh button calls, for a parent that changes the directory
   *  itself — a save — and wants the new file listed without the author pressing `↻`. */
  refreshRef?: (refresh: () => void) => void;
};

export function FilePicker(props: FilePickerProps) {
  // Asked once at mount, and again on the button. A memo over the promise asked exactly once:
  // if the server was still starting, `postRequest` answered `null`, the list stayed empty and
  // nothing asked again, a reload during the same boot giving the same nothing. The server walks
  // the directory on every request, so asking is all it takes.
  //
  // One listing for every picker: `list-files` names each file's kind, and tables, cards and
  // filters documents are confined to the same directory through the same control.
  const [files, setFiles] = createSignal<Listed[]>([]);
  // `true` from the start rather than set on the way in: Solid 2 refuses a signal write during a
  // component's own setup (`REACTIVE_WRITE_IN_OWNED_SCOPE`), and the first request goes out
  // from exactly there. The replies write from a microtask, which is fine.
  const [asking, setAsking] = createSignal(true);
  const request = () =>
    postRequest("list-files", {}, null)
      .then((answer: unknown) => setFiles(Array.isArray(answer) ? (answer as Listed[]) : []))
      .finally(() => setAsking(false));
  void request();
  function ask() {
    setAsking(true);
    void request();
  }
  // Handed over once, like a `ref`: the parent keeps the function, there is nothing to track.
  untrack(() => props.refreshRef)?.(ask);
  const options = () =>
    files()
      .filter((file) => file.kind === props.kind)
      .map((file) => ({ label: file.path, value: file.path }));
  const selectClass = "text-primary font-semibold py-2 w-full text-left";
  const id = _.uniqueId("load_");
  return (
    <>
      <label for={id} class={selectClass}>
        {props.label ?? "Choose files"}
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
