import { Select, createOptions } from "@thisbeyond/solid-select";
import { createResource } from 'solid-js';
import { postRequest } from "../requests";
import * as _ from "lodash";

export function FilePicker(props) {
    const [files] = createResource(() => postRequest("get-acceptable-paths", {}, null));
    const selProps = createOptions(() => files() || []);
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = _.uniqueId("load_");
    return <>
        <label for={id} class={selectClass}>Choose files</label>
        <Select id={id} required={props.required} onChange={props.onChange}
            multiple={props.multiple} {...selProps}></Select>
    </>;
}
