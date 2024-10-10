import { createStore } from "solid-js/store"

import { IntervalFilter } from "../components/interval-filter";
import { ListFilter } from "../components/list-filter";
import { Button } from "../components/button";

export function Filters(props) {
    const [store, setStore] = createStore({numerical: {}, categorical: {}})

    const numerical = () => props.metadata
        .filter(entry => entry.type == "numerical")
        .map(entry => Object.assign(
            {},
            entry,
            {"onValue": (x) => setStore("numerical", {[entry.name]: x})}
        ));
    const categorical = () => props.metadata
        .filter(entry => entry.type == "categorical")
        .map(entry => Object.assign(
            {},
            entry,
            {"onValue": (x) => setStore("categorical", {[entry.name]: x})}
        ));

    return <div>
        <div class="flex flex-row gap-4">
            <div class="basis-1/2"><For each={numerical()}>{IntervalFilter}</For></div>
            <div class="basis-1/2"><For each={categorical()}>{ListFilter}</For></div>
        </div>
        <div class="p-4">
            <Button positive onClick={() => props.onValue(store)}>Filter</Button>
        </div>
    </div>;
}
