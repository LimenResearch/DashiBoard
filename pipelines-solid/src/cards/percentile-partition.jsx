import { createSignal } from "solid-js"
import { Select, createOptions } from "@thisbeyond/solid-select"
import { Input } from "../components/input";
import { setKey } from "../components/card";

class PercentilePartition {
    constructor (order_by, by, p, output) {
        this.type = "percentile_partition";
        this.order_by = order_by;
        this.by = by;
        this.p = p;
        this.output = output;
    }

    getOutputs() {
        return [{name: this.output}];
    }

    clone() {
        return new PercentilePartition(this.order_by, this.by, this.p, this.output);
    }
}

export function initPercentilePartitionCard() {
    const init = new PercentilePartition([], [], NaN, "partition");
    const [value, setValue] = createSignal(init);
    const setter = (k, v) => setKey([value, setValue], k, v);
    return {input: [value, setter], output: value};
}

export function PercentilePartitionCard(props) {
    const [value, setter] = props.input;
    const init = value(); // avoid reactivity here
    const selProps = createOptions(() => props.metadata.map(x => x.name));
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "order_by"} class={selectClass}>Order</label>
        <Select id={id + "order_by"} onChange={x => setter("order_by", x)}
            class="mb-2" multiple {...selProps} onClick></Select>

        <label for={id + "by"} class={selectClass}>Group</label>
        <Select id={id + "by"} onChange={x => setter("by", x)}
            class="mb-2" multiple {...selProps}></Select>

        <label for={id + "p"} class={selectClass}>Percentile</label>
        <Input id={id + "p"} onChange={ev => setter("p", parseFloat(ev.target.value))}
            class="w-full mb-2" type="number" min="0" max="1" step="0.01"
            placeholder="Select..."></Input>

        <label for={id + "output"} class={selectClass}>Output</label>
        <Input id={id + "output"} value={init.output}
            onChange={ev => setter("output", ev.target.value)}
            class="w-full mb-2" type="text" placeholder="Select..."></Input>
    </>;
}
