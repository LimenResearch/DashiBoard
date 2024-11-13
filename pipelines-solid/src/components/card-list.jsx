import { initCard, Card, CardPlus } from "./card";

export function CardList(props) {
    const [store, setStore] = props.input;

    const addCardAfter = (name, card) => {
        const data = initCard({name});
        const i = store.cards.indexOf(card);
        setStore("cards", store.cards.toSpliced(i + 1, 0, { name, ...data }));
    };

    return <>
        <CardPlus onClick={addCardAfter}></CardPlus>
        <For each={store.cards}>
            {card => {
                const onClose = () => setStore("cards", store.cards.filter(x => x !== card));
                return <>
                    <Card onClose={onClose} metadata={props.metadata} {...card}></Card>
                    <CardPlus onClick={name => addCardAfter(name, card)}></CardPlus>
                </>;
            }}
        </For>
    </>;
}
