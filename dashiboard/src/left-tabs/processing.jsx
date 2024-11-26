import { createStore } from "solid-js/store";
import { CardList } from "../components/card-list";

export function initPipeline() {
    const [store, setStore] = createStore({cards: []});
    const input = [store, setStore];
    const output = () => store.cards.map(card => card.output());
    return {input, output};
}

export function Pipeline(props) {
    return <CardList {...props}></CardList>
}