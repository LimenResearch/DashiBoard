import { createSignal } from "solid-js";
import { Select } from "@thisbeyond/solid-select";

import { CardContent, initCardContent } from "./content";
import { CARD_CONFIGS } from "./configs"

// TODO: generate CARD_CONFIGS from julia

export const CARD_MAP = new Map();

for (const card of CARD_CONFIGS) {
    CARD_MAP.set(card.label, card.type)
}

export function initCard(props) {
    const type = CARD_MAP.get(props.name);
    return initCardContent(type);
}

export function Card(props) {
    return <div class="bg-white w-full p-4">
        <span class="text-blue-800 text-xl font-semibold">{props.name}</span>
        <span onClick={props.onClose}
            class="text-red-800 hover:text-red-900 text-xl font-semibold float-right cursor-pointer">
            ✕
        </span>
        <div class="mt-2">
            <CardContent type={CARD_MAP.get(props.name)} {...props}></CardContent>
        </div>
    </div>;
}

export function CardPlus(props) {
    const [initialValue, setInitialValue] = createSignal(null,  { equals: false });
    const [listVisible, setListVisible] = createSignal(false);
    const cardKeys = Array.from(CARD_MAP.keys());
    const onClick = () => {
        setListVisible(!listVisible());
        setInitialValue(null);
    }
    const onChange = x => {
        x && props.onClick(x);
    }
    const plusClass = "h-7 font-bold text-lg text-gray-900 hover:text-gray-1000 hover:bg-gray-200";

    return <div class="grid grid-cols-2 gap-4 py-2 my-2">
        <button class={plusClass} onClick={onClick}>
            {listVisible() ? "－" : "＋"}
        </button>
        <Show when={listVisible()}>
            <div class="h-7">
                <Select initialValue={initialValue()} options={cardKeys} onChange={onChange}></Select>
            </div>
        </Show>
    </div>;
}
