import { createSignal } from "solid-js"

export function initPercentilePartition() {
    const [value, setValue] = createSignal("");
    return {input: {value, setValue}, output: value};
}

export function PercentilePartition(props) {
    const { input } = props;
    return <input type="text" value={input.value()}
        onChange={e => input.setValue(e.target.value)}></input>;
}
