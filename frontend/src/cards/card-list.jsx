import { createResource } from "solid-js";
import { Card, CardPlus } from "./card";
import { postRequest } from "../requests";

export function CardList(props) {
    const [store, setStore] = props.input;
    const [configs] = createResource(
        () => postRequest("get-card-configurations", {}, null)
    );
    const safeConfigs = () => configs() || [];

    const options = () => safeConfigs().map(x => x.label);
    const addCardAfter = (label, i) => {
        const config = safeConfigs().find(x => x.label === label);
        setStore("cards", cards => cards.toSpliced(i + 1, 0, config));
    };

    return <>
        <CardPlus onClick={addCardAfter} options={options()}></CardPlus>
        <For each={store.cards}>
            {(card, index) => {
                return <>
                    <Card input={props.input} metadata={props.metadata} index={index()} {...card}/>
                    <CardPlus onClick={label => addCardAfter(label, index())} options={options()}/>
                </>;
            }}
        </For>
    </>;
}
