import { createStore } from "solid-js/store";
import { CardList } from "../components/card-list"

export function initPipeline() {
    const [store, setStore] = createStore({
        cards: [
            { name: "Percentile Partition", id: 1, input: {value: () => "aa"}},
        ]
    });
    const input = [store, setStore];
    const output = store;
    return {input, output};
}

export function Pipeline(props) {
    return <CardList {...props}></CardList>
}