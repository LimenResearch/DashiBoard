import { Select, createOptions } from "@thisbeyond/solid-select";
import { createResource } from 'solid-js';
import { postRequest } from "../requests";

export function FilePicker(props) {
    const [files] = createResource(() => postRequest("get-acceptable-paths", {}, null));
    const selProps = createOptions(() => files() || []);
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "load"} class={selectClass}>Choose files</label>
        <Select id={id + "load"} required={props.required} onChange={props.onChange}
            multiple={props.multiple} {...selProps}></Select>
    </>;
}
