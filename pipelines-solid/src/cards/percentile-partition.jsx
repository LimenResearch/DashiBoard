import { createSignal } from "solid-js"
import { Select, createOptions } from "@thisbeyond/solid-select"
import { Input } from "../components/input";

export function initPercentilePartition() {
    const init = {
        type: "percentile_partition",
        order_by: [],
        by: [],
        p: NaN,
        output: ""
    };
    const [value, setValue] = createSignal(init);
    const setKey = (k, v) => setValue(Object.assign({}, value(), {[k]: v}));
    return {input: [value, setKey], output: value};
}

export function PercentilePartition(props) {
    const [value, setKey] = props.input;
    const selProps = createOptions(() => props.metadata.map(x => x.name));
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "order_by"} class={selectClass}>Order</label>
        <Select id={id + "order_by"} onChange={x => setKey("order_by", x)}
            class="mb-2" multiple {...selProps} onClick></Select>

        <label for={id + "by"} class={selectClass}>Group</label>
        <Select id={id + "by"} onChange={x => setKey("by", x)}
            class="mb-2" multiple {...selProps}></Select>

        <label for={id + "p"} class={selectClass}>Percentile</label>
        <Input id={id + "p"} onChange={ev => setKey("p", parseFloat(ev.target.value))}
            class="w-full mb-2" type="number" min="0" max="1" step="0.01"
            placeholder="Select..."></Input>

        <label for={id + "output"} class={selectClass}>Output</label>
        <Input id={id + "output"} onChange={ev => setKey("output", ev.target.value)}
            class="w-full mb-2" type="text" placeholder="Select..."></Input>
    </>;
}
