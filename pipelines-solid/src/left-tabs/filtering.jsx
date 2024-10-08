import { IntervalFilter } from "../components/interval-filter";

export function Filters(props) {
    return <For each={props.intervals}>
        {item => IntervalFilter(item)}
    </For>;
}
