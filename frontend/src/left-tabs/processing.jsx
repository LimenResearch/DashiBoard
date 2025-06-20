import { createStore } from "solid-js/store";
import { DownloadJSON, UploadJSON } from "../components/json";
import { CardList } from "../cards/card-list";
import { cardValue } from "../cards/card";

export function initPipeline() {
    const [store, setStore] = createStore({cards: []});
    const input = [store, setStore];
    const output = () => store.cards.map(cardValue);
    return {input, output};
}

export function Pipeline(props) {
    const [store, setStore] = props.input;

    return <>
        <CardList input={props.input} metadata={props.metadata}></CardList>
        <DownloadJSON data={store} name="cards.json">
            Download cards
        </DownloadJSON>
        <UploadJSON def={store} onChange={setStore}>
            Upload cards
        </UploadJSON>
    </>;
}