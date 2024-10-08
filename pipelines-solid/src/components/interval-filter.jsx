import { createMemo, createSignal } from "solid-js";
import { Toggler } from "./toggler";

function something(a, b) {
    return a == null ? b : a;
}

export function IntervalFilter(props) {
    const [leftValue, setLeftValue] = createSignal(null);
    const [rightValue, setRightValue] = createSignal(null);

    function updateValid(setter, value) {
        const val = parseFloat(value);
        isNaN(val) || setter(val);
    }

    const modified = createMemo(() => {
        return leftValue() != null || rightValue() != null;
    });

    const onReset = () => {
        setLeftValue(null);
        setRightValue(null);
    }

    const leftInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={something(leftValue(), props.summary.min)}
        oninput={e => updateValid(setLeftValue, e.target.value)}
    ></input>;

    const rightInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={something(rightValue(), props.summary.max)}
        oninput={e => updateValid(setRightValue, e.target.value)}
    ></input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        {filterForm}
    </Toggler>;
}