import { Toggler } from "./toggler";

class Interval {
    constructor(left, right) {
        this.left = left;
        this.right = right;
    }

    isTrivial() {
        return this.left == null && this.right == null;
    }

    copy() {
        return new Interval(this.left, this.right);
    }
}

export function IntervalFilter(props) {
    const filterValue = () => props.store.numerical[props.name] || new Interval();
    const setFilterValue = value => props.setStore("numerical", { [props.name]: value });

    const leftValue = () => filterValue().left == null ? props.summary.min : filterValue().left;
    const rightValue = () => filterValue().right == null ? props.summary.max : filterValue().right;

    function updateValid(input, side, limit) {
        let value = parseFloat(input);
        if (!isNaN(value)) {
            (value === limit) && (value = null);
            const newFilterValue = filterValue().copy();
            newFilterValue[side] = value;
            setFilterValue(newFilterValue);
        }
    }

    const onReset = () => setFilterValue(null);

    const leftInput = <input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={leftValue()}
        oninput={e => updateValid(e.target.value, "left", props.summary.min)}
    ></input>;

    const rightInput = <input
        type="number"
        min={props.summary.min + (props.summary.max - props.summary.min) % props.summary.step}
        max={props.summary.max}
        step={props.summary.step}
        value={rightValue()}
        oninput={e => updateValid(e.target.value, "right", props.summary.max)}
    ></input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name} modified={!filterValue().isTrivial()} onReset={onReset}>
        {filterForm}
    </Toggler>;
}
