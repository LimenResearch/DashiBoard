import { Input } from "../components/input";
import { Toggler } from "../components/toggler";

class Interval {
    constructor(min, max) {
        this.min = min;
        this.max = max;
    }

    clone() {
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
        let interval = filterValue().clone();
        interval[k] = value;
        if (interval.min === props.summary.min  && interval.max === props.summary.max) {
            interval = null;
        }
        setFilterValue(interval);
    }

    const onReset = () => setFilterValue(null);

    const leftInput = <Input
        type="number"
        min={props.summary.min}
        max={props.summary.max}
        step={props.summary.step}
        value={filterValue().min}
        onChange={e => updateValid(e.target.value, "min")}
    ></Input>;

    const rightInput = <Input
        type="number"
        min={props.summary.min + (props.summary.max - props.summary.min) % props.summary.step}
        max={props.summary.max}
        step={props.summary.step}
        value={filterValue().max}
        onChange={e => updateValid(e.target.value, "max")}
    ></Input>;

    const filterForm = <form class="flex justify-between">
        {leftInput}
        {rightInput}
    </form>;

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        {filterForm}
    </Toggler>;
}
