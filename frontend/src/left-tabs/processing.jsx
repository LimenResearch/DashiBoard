import { createStore } from "solid-js/store";
import { CardList } from "../cards/card-list";

export function initPipeline() {
    const [store, setStore] = createStore({cards: []});
    const input = [store, setStore];
    // TODO: also use validity info
    const output = () => store.cards.map(card => card.output.value());
    return {input, output};
}

export function Pipeline(props) {
    return <CardList {...props}></CardList>
}