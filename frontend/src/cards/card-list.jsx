import { initCard, Card, CardPlus } from "./card";
import { getOutputs } from "./content";

export function CardList(props) {
    const [store, setStore] = props.input;

    const addCardAfter = (name, card) => {
        const data = initCard({name});
        const i = store.cards.indexOf(card);
        setStore(
            "cards",
            store.cards.toSpliced(
                i + 1,
                0,
                { name, input: data.input, output: data.output }
            )
        );
    };

    const metadata = card => {
        const newNames = store.cards
            .filter(x => x !== card)
            .map(x => getOutputs(x.output()))
            .flat();
        return props.metadata.concat(newNames);
    };

    return <>
        <CardPlus onClick={addCardAfter}></CardPlus>
        <For each={store.cards}>
            {card => {
                const onClose = () => setStore("cards", store.cards.filter(x => x !== card));
                return <>
                    <Card onClose={onClose} metadata={metadata(card)} {...card}></Card>
                    <CardPlus onClick={name => addCardAfter(name, card)}></CardPlus>
                </>;
            }}
        </For>
    </>;
}
