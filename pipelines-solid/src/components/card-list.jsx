import { Card } from "./card";

export function CardList(props) {
    const [store, setStore] = props.input;

    return <For each={store.cards}>
        {props => {
            const onClose = () => setStore("cards", store.cards.filter(x => x.id !== props.id));
            return <Card onClose={onClose} {...props}></Card>;
        }}
    </For>;
}