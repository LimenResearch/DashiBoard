import fs from 'vite-plugin-fs/browser';

import { Select, createOptions } from "@thisbeyond/solid-select";
import { createResource } from 'solid-js';

function acceptable(name, extensions) {
    return extensions.some(x => name.endsWith(x));
}

// TODO: allow files in nested directories
async function readDir(input) {
    const {source, extensions} = input;
    const files = await fs.readdir(source);
    return files.filter(name => acceptable(name, extensions));
}

export function FilePicker(props) {
    const input = () => ({source: props.source, extensions: props.extensions});
    const [files] = createResource(input, readDir);
    const selProps = createOptions(() => files() || []);
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "load"} class={selectClass}>Choose files</label>
        <Select id={id + "load"} onChange={props.onChange}
            multiple={props.multiple} {...selProps}></Select>
    </>;
}
