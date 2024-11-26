import { Select, createOptions } from "@thisbeyond/solid-select";
import { createResource } from 'solid-js';
import { postRequest } from "../requests";

function acceptable(name, extensions) {
    return extensions.some(x => name.endsWith(x));
}

export function FilePicker(props) {
    const [files] = createResource(() => postRequest("list").then(x => x.json()));
    const selProps = createOptions(() => files() || []);
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "load"} class={selectClass}>Choose files</label>
        <Select id={id + "load"} onChange={props.onChange}
            multiple={props.multiple} {...selProps}></Select>
    </>;
}