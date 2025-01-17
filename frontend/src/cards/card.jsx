import { createSignal } from "solid-js";
import { Select } from "@thisbeyond/solid-select";

import { CardContent, initCardContent } from "./card-content";

// TODO: generate CARD_CONFIGS from julia

export function initCard(config) {
    return initCardContent(config);
}

export function Card(props) {
    return <div class="bg-white w-full p-4">
        <span class="text-blue-800 text-xl font-semibold">{props.label}</span>
        <span onClick={props.onClose}
            class="text-red-800 hover:text-red-900 text-xl font-semibold float-right cursor-pointer">
            ✕
        </span>
        <div class="mt-2">
            <CardContent config={props.config} input={props.input}
                metadata={props.metadata}></CardContent>
        </div>
    </div>;
}

export function CardPlus(props) {
    const [initialValue, setInitialValue] = createSignal(null,  { equals: false });
    const [listVisible, setListVisible] = createSignal(false);
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
                <Select initialValue={initialValue()} options={props.options}
                    onChange={onChange}></Select>
            </div>
        </Show>
    </div>;
}
