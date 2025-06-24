import { createResource, useContext } from "solid-js";
import { createStore } from "solid-js/store";

import { DownloadJSON, UploadJSON } from "../components/json";
import { Card, CardPlus, cardValue } from "../cards/card";
import { postRequest } from "../requests";
import { CardsContext } from "../create";

export function initCards(metadata) {
    const [state, setState] = createStore({cards: []});
    return {state, setState, metadata};
}

export function getCards(state) {
    return state.cards.map(cardValue);
}

export function Cards() {
    const {state, setState} = useContext(CardsContext);
    const [configs] = createResource(
        () => postRequest("get-card-configurations", {}, null)
    );
    const safeConfigs = () => configs() || [];

    const options = () => safeConfigs().map(x => x.label);
    const addCardAfter = (label, i) => {
        const config = safeConfigs().find(x => x.label === label);
        setState("cards", cards => cards.toSpliced(i + 1, 0, config));
    };

    return <>
        <CardPlus onClick={addCardAfter} options={options()}></CardPlus>
        <For each={state.cards}>
            {(card, index) => {
                return <>
                    <Card index={index()} {...card}/>
                    <CardPlus onClick={label => addCardAfter(label, index())} options={options()}/>
                </>;
            }}
        </For>
        <DownloadJSON data={state} name="cards.json">
            Download cards
        </DownloadJSON>
        <UploadJSON def={state} onChange={setState}>
            Upload cards
        </UploadJSON>
    </>;
}