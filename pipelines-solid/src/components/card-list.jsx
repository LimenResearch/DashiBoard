import { createSignal } from "solid-js";

import { Card, CARD_MAP } from "./card";

export function CardList(props) {
    const [store, setStore] = props.input;
    const plusClass = "w-full text-2xl font-bold py-2 text-gray-900 hover:text-gray-1000 hover:bg-gray-200";
    const keyClass = "cursor-pointer text-center text-xl py-2 text-gray-900";
    const cardKeys = Array.from(CARD_MAP.keys());
    const [listVisible, setListVisible] = createSignal(false);

    return <>
        <For each={store.cards}>
            {props => {
                const onClose = () => setStore("cards", store.cards.filter(x => x.id !== props.id));
                return <Card onClose={onClose} {...props}></Card>;
            }}
        </For>
        <button class={plusClass} onClick={() => setListVisible(true)}>＋</button>
        <ul class="w-full">
            <Show when={listVisible()}>
                <For each={cardKeys}>
                    {k => {
                        const onClick = () => {
                            console.log(k);
                            setListVisible(false);
                        };
                        return <li class={keyClass} onClick={onClick}>{k}</li>;
                    }}
                </For>
            </Show>
        </ul>
    </>;
}