import { Toggler } from "./toggler";

class Interval {
    constructor(left, right) {
        this.left = left;
        this.right = right;
    }

    copy() {
        return new Interval(this.left, this.right);
    }
}

export function IntervalFilter(props) {
    const modified = () => props.store.numerical[props.name] != null
    const filterValue = () => modified() ?
        props.store.numerical[props.name] :
        new Interval(props.summary.min, props.summary.max);
    const setFilterValue = value => props.setStore("numerical", { [props.name]: value });

    function updateValid(input, side) {
        const value = parseFloat(input);
        if (!isNaN(value)) {
            let interval = filterValue().copy();
            interval[side] = value;
            if (interval.left === props.summary.min  && interval.right === props.summary.max) {
                interval = null;
            }
            setFilterValue(interval);
        }
    }

    const onReset = () => setFilterValue(null);

    const leftInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={filterValue().left}
        oninput={e => updateValid(e.target.value, "left")}
    ></input>;

    const rightInput = <input
        type="number"
        min={props.summary.min + (props.summary.max - props.summary.min) % props.summary.step}
        max={props.summary.max}
        step={props.summary.step}
        value={filterValue().right}
        oninput={e => updateValid(e.target.value, "right")}
    ></input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        {filterForm}
    </Toggler>;
}
