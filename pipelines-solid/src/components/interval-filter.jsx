import { Toggler } from "./toggler";

export function IntervalFilter(props) {
    const leftInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={props.summary.min}
    ></input>;

    const rightInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={props.summary.max}
    ></input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name}>
        {filterForm}
    </Toggler>;
}