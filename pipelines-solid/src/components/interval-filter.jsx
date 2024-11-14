import { Toggler } from "./toggler";

class Interval {
    constructor(min, max) {
        this.min = min;
        this.max = max;
    }

    copy() {
        return new Interval(this.min, this.max);
    }
}

export function IntervalFilter(props) {
    const modified = () => props.store.numerical[props.name] != null
    const filterValue = () => modified() ?
        props.store.numerical[props.name] :
        new Interval(props.summary.min, props.summary.max);
    const setFilterValue = value => props.setStore("numerical", { [props.name]: value });

    function updateValid(input, k) {
        const value = parseFloat(input);
        let interval = filterValue().copy();
        interval[k] = value;
        if (interval.min === props.summary.min  && interval.max === props.summary.max) {
            interval = null;
        }
        setFilterValue(interval);
    }

    const onReset = () => setFilterValue(null);

    const className = `pl-2 py-0.5 rounded border outline-none border-gray-200
        ring-offset-2 focus:ring-2 focus:ring-gray-300`;

    const leftInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        class={className}
        value={filterValue().min}
        onChange={e => updateValid(e.target.value, "min")}
    ></input>;

    const rightInput = <input
        type="number"
        min={props.summary.min + (props.summary.max - props.summary.min) % props.summary.step}
        max={props.summary.max}
        step={props.summary.step}
        class={className}
        value={filterValue().max}
        onChange={e => updateValid(e.target.value, "max")}
    ></input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        {filterForm}
    </Toggler>;
}
