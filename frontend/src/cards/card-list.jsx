import { createResource } from "solid-js";
import { initCard, Card, CardPlus } from "./card";
import { getOutputs } from "./card-content";
import { postRequest } from "../requests";

export function CardList(props) {
    const [store, setStore] = props.input;
    const [configs] = createResource(
        () => postRequest("get-card-configurations", {}, null)
    );

    const options = () => (configs() || []).map(x => x.label);

    const addCardAfter = (label, card) => {
        const config = (configs() || []).find(x => x.label === label);
        const data = initCard(config);
        const i = store.cards.indexOf(card);
        setStore(
            "cards",
            store.cards.toSpliced(
                i + 1,
                0,
                { config, input: data.input, output: data.output }
            )
        );
    };

    const metadata = card => {
        const newNames = store.cards
            .filter(x => x !== card)
            .flatMap(x => getOutputs(x.config, x.output.value()));
        return props.metadata.concat(newNames);
    };

    return <>
        <CardPlus onClick={addCardAfter} options={options()}></CardPlus>
        <For each={store.cards}>
            {card => {
                const onClose = () => setStore("cards", store.cards.filter(x => x !== card));
                return <>
                    <Card onClose={onClose} metadata={metadata(card)} {...card}></Card>
                    <CardPlus onClick={label => addCardAfter(label, card)}
                        options={options()}></CardPlus>
                </>;
            }}
        </For>
    </>;
}
