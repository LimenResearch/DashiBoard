import { initCard, Card, CardPlus } from "./card";
import { getOutputs } from "./card-content";
import { CARD_CONFIGS } from "./configs"

export function CardList(props) {
    const [store, setStore] = props.input;

    const options = CARD_CONFIGS.map(x => x.label);

    const addCardAfter = (label, card) => {
        const config = CARD_CONFIGS.find(x => x.label === label);
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
            .map(x => getOutputs(x.config, x.output()))
            .flat();
        return props.metadata.concat(newNames);
    };

    return <>
        <CardPlus onClick={addCardAfter} options={options}></CardPlus>
        <For each={store.cards}>
            {card => {
                const onClose = () => setStore("cards", store.cards.filter(x => x !== card));
                return <>
                    <Card onClose={onClose} metadata={metadata(card)} {...card}></Card>
                    <CardPlus onClick={label => addCardAfter(label, card)}
                        options={options}></CardPlus>
                </>;
            }}
        </For>
    </>;
}
