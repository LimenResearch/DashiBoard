import { createSignal } from "solid-js"
import { Select, createOptions } from "@thisbeyond/solid-select"

export function initPercentilePartition() {
    const init = {
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
    const number = `mb-2 pl-2 py-0.5 w-full rounded border outline-none border-gray-200
        ring-offset-2 focus:ring-2 focus:ring-gray-300`;
    const id = crypto.randomUUID();
    return <>
        <label for={id + "order_by"} class={selectClass}>Order</label>
        <Select id={id + "order_by"} onChange={x => setKey("order_by", x)}
            class="mb-2" multiple {...selProps} onClick></Select>

        <label for={id + "by"} class={selectClass}>Group</label>
        <Select id={id + "by"} onChange={x => setKey("by", x)}
            class="mb-2" multiple {...selProps}></Select>

        <label for={id + "p"} class={selectClass}>Percentile</label>
        <input id={id + "p"} onChange={ev => setKey("p", parseFloat(ev.target.value))}
            class={number} type="number" min="0" max="1" step="0.01"
            placeholder="Select..."></input>

        <label for={id + "output"} class={selectClass}>Output</label>
        <Select id={id + "output"} onChange={x => setKey("output", x)}
            class="mb-2" {...selProps}></Select>
    </>;
}
