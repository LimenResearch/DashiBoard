import { createSignal } from "solid-js"
import { Select, createOptions } from "@thisbeyond/solid-select"
import { Input } from "../components/input";
import { setKey } from "../components/card";

// TODO: cache summary statistics?

const methods = ["zscore", "maxabs", "minmax", "log", "logistic"]

class Rescale {
    constructor (method, by, columns, suffix) {
        this.type = "rescale";
        this.method = method;
        this.columns = columns
        this.by = by;
        this.suffix = suffix;
    }

    getOutputs() {
        return this.by.map(x => ({name: x + '_' + this.suffix}));
    }

    clone() {
        return new Rescale(this.method, this.by, this.columns, this.suffix);
    }
}

export function initRescaleCard() {
    const init = new Rescale("", [], [], "rescaled");
    const [value, setValue] = createSignal(init);
    const setter = (k, v) => setKey([value, setValue], k, v);
    return {input: [value, setter], output: value};
}

export function RescaleCard(props) {
    const [value, setter] = props.input;
    const init = value(); // avoid reactivity here
    const methodProps = createOptions(methods);
    const selProps = createOptions(() => props.metadata.map(x => x.name));
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "method"} class={selectClass}>Method</label>
        <Select id={id + "method"} onChange={x => setter("method", x)}
            class="mb-2" {...methodProps}></Select>

        <label for={id + "by"} class={selectClass}>Group</label>
        <Select id={id + "by"} onChange={x => setter("by", x)}
            class="mb-2" multiple {...selProps}></Select>

        <label for={id + "columns"} class={selectClass}>Columns</label>
        <Select id={id + "columns"} onChange={x => setter("columns", x)}
            class="mb-2" multiple {...selProps}></Select>

        <label for={id + "suffix"} class={selectClass}>Suffix</label>
        <Input id={id + "suffix"} value={init.suffix}
            onChange={ev => setter("suffix", ev.target.value)}
            class="w-full mb-2" type="text" placeholder="Select..."></Input>
    </>;
}
