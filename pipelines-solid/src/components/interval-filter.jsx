export function IntervalFilter(props) {
    const leftInput = <input
        type="number"
        min={props.min}
        max={props.max}
        step={props.step}
        value={props.min}
    ></input>

    const rightInput = <input
        type="number"
        min={props.min}
        max={props.max}
        step={props.step}
        value={props.max}
    ></input>

    return <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;
}