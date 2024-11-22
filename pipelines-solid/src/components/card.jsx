import { createSignal } from "solid-js";
import { Select } from "@thisbeyond/solid-select";

import { SplitCard, initSplitCard } from "../cards/split"
import { initRescaleCard, RescaleCard } from "../cards/rescale";

export function setKey([value, setValue], k, v) {
    const newValue = value().clone();
    newValue[k] = v;
    setValue(newValue);
}

export const CARD_MAP = new Map();

CARD_MAP.set(
    "Split",
    { init: initSplitCard, component: SplitCard }
);

CARD_MAP.set(
    "Rescale",
    { init: initRescaleCard, component: RescaleCard }
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
