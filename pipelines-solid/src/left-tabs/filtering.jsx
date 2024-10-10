import { createStore } from "solid-js/store"

import { IntervalFilter } from "../components/interval-filter";
import { ListFilter } from "../components/list-filter";

export function Filters(props) {
    const [store, setStore] = createStore({numerical: {}, categorical: {}})
    const numerical = () => props.metadata
        .filter(entry => entry.type == "numerical")
        .map(entry => Object.assign(
            {},
            entry,
            {"onValue": (x) => setStore("numerical", {[entry.name]: x})}
        ));
    const categorical = () => props.metadata.filter(x => x.type == "categorical");

    const intervalFilters = <For each={numerical()}>
        {IntervalFilter}
    </For>;
    const listFilters = <For each={categorical()}>
        {ListFilter}
    </For>;

    return <div class="flex flex-row gap-4">
        <div class="basis-1/2">{intervalFilters}</div>
        <div class="basis-1/2">{listFilters}</div>
    </div>;
}
