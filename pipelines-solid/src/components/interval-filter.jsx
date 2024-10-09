import { createMemo, createSignal } from "solid-js";
import { Toggler } from "./toggler";

function something(a, b) {
    return a == null ? b : a;
}

export function IntervalFilter(props) {
    const [_leftValue, _setLeftValue] = createSignal(null);
    const [_rightValue, _setRightValue] = createSignal(null);

    const leftValue = () => something(_leftValue(), props.summary.min);
    const rightValue = () => something(_rightValue(), props.summary.max);

    function updateValid(setter, value) {
        const val = parseFloat(value);
        isNaN(val) || setter(val);
    }

    const modified = createMemo(() => {
        return leftValue() !== props.summary.min || rightValue() !== props.summary.max;
    });

    const onReset = () => {
        _setLeftValue(null);
        _setRightValue(null);
    }

    const leftInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={leftValue()}
        oninput={e => updateValid(_setLeftValue, e.target.value)}
    ></input>;

    const rightInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={rightValue()}
        oninput={e => updateValid(_setRightValue, e.target.value)}
    ></input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        {filterForm}
    </Toggler>;
}
