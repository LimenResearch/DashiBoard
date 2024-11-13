import { createSignal } from "solid-js";
import { PercentilePartition, initPercentilePartition } from "../cards/percentile-partition"

export const CARD_MAP = new Map();

CARD_MAP.set(
    "Percentile Partition",
    { init: initPercentilePartition, component: PercentilePartition }
);

export function initCard(props) {
    return CARD_MAP.get(props.name).init();
}

export function Card(props) {

    const children = CARD_MAP.get(props.name).component(props);

    return <div class="bg-white w-full p-4">
        <span class="text-blue-800 text-xl font-semibold">{props.name}</span>
        <span onClick={props.onClose}
            class="text-red-800 hover:text-red-900 text-xl font-semibold float-right cursor-pointer">
            ✕
        </span>
        <div class="mt-2">
            {children}
        </div>
    </div>
}

export function CardPlus(props) {
    const plusClass = "w-full text-2xl font-bold py-2 text-gray-900 hover:text-gray-1000 hover:bg-gray-200";
    const keyClass = "cursor-pointer text-center text-xl py-2 text-gray-900";
    const cardKeys = Array.from(CARD_MAP.keys());
    const [listVisible, setListVisible] = createSignal(false);
    return <>
        <button class={plusClass} onClick={() => setListVisible(true)}>＋</button>
        <ul class="w-full">
            <Show when={listVisible()}>
                <For each={cardKeys}>
                    {k => {
                        const onClick = () => {
                            props.onClick(k);
                            setListVisible(false);
                        }
                        return <li class={keyClass} onClick={onClick}>{k}</li>;
                    }}
                </For>
            </Show>
        </ul>
    </>;
}
