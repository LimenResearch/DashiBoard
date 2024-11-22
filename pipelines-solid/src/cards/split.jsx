import { createSignal } from "solid-js"
import { Select, createOptions } from "@thisbeyond/solid-select"
import { Input } from "../components/input";
import { setKey } from "../components/card";

const methods = ["percentile", "tiles"];

class Split {
    constructor (method, order_by, by, output, p, tiles) {
        this.type = "split";
        this.method = method;
        this.order_by = order_by;
        this.by = by;
        this.output = output;
        this.p = p;
        this.tiles = tiles;
    }

    getOutputs() {
        return [{name: this.output}];
    }

    clone() {
        return new Split(this.method, this.order_by, this.by, this.output, this.p, this.tiles);
    }
}

export function initSplitCard() {
    const init = new Split([], [], NaN, "partition");
    const [value, setValue] = createSignal(init);
    const setter = (k, v) => setKey([value, setValue], k, v);
    return {input: [value, setter], output: value};
}

export function SplitCard(props) {
    const [value, setter] = props.input;
    const init = value(); // avoid reactivity here
    const methodProps = createOptions(methods);
    const splitProps = createOptions(["1", "2"]);
    const selProps = createOptions(() => props.metadata.map(x => x.name));
    const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";
    const id = crypto.randomUUID();
    return <>
        <label for={id + "method"} class={selectClass}>Method</label>
        <Select id={id + "method"} onChange={x => setter("method", x)}
            class="mb-2" {...methodProps}></Select>

        <label for={id + "order_by"} class={selectClass}>Order</label>
        <Select id={id + "order_by"} onChange={x => setter("order_by", x)}
            class="mb-2" multiple {...selProps} onClick></Select>

        <label for={id + "by"} class={selectClass}>Group</label>
        <Select id={id + "by"} onChange={x => setter("by", x)}
            class="mb-2" multiple {...selProps}></Select>

        <label for={id + "output"} class={selectClass}>Output</label>
        <Input id={id + "output"} value={init.output}
            onChange={ev => setter("output", ev.target.value)}
            class="w-full mb-2" type="text" placeholder="Select..."></Input>

        <Show when={value().method == "percentile"}>
        <label for={id + "p"} class={selectClass}>Percentile</label>
        <Input id={id + "p"} onChange={ev => setter("p", parseFloat(ev.target.value))}
            class="w-full mb-2" type="number" min="0" max="1" step="0.01"
            placeholder="Select..."></Input>
        </Show>

        <Show when={value().method == "tiles"}>
        <label for={id + "tiles"} class={selectClass}>Tiles</label>
        <Select id={id + "tiles"} onChange={x => setter("tiles", x.map(s => parseInt(s)))}
            class="mb-2" multiple {...splitProps}></Select>
        </Show>
    </>;
}
