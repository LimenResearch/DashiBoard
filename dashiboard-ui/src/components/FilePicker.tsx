import { Combobox } from "./Combobox";

import { createMemo } from "solid-js";
import { postRequest } from "../requests";
import * as _ from "lodash";

type FilePickerProps = {
  required?: boolean;
  onChange?: (value: string | string[]) => void;
  multiple?: boolean;
};

export function FilePicker(props: FilePickerProps) {
  const files = createMemo(() =>
    postRequest("get-acceptable-paths", {}, null),
  );
  const options = () => {
    const vals = files() ?? [];
    return vals.map((x: string) => ({label: x, value: x}));
  }
  const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
  const id = _.uniqueId("load_");
  return (
    <>
      <label for={id} class={selectClass}>
        Choose files
      </label>
      <Combobox
        id={id}
        required={props.required}
        onChange={props.onChange}
        multiple={props.multiple}
        options={options()}
      ></Combobox>
    </>
  );
}
