import * as _ from "lodash";
import { Select } from "@thisbeyond/solid-select";
import { createSignal } from "solid-js";

import { AutoWidget } from "./auto-widget";

export function getOutputs(config) {
    const g = _cardValue(config);
    const { field, suffixField, numberField } = config.output;
    let names = g[field];
    names = Array.isArray(names) ? names : [names];

    if (suffixField != null) {
        names = names.map(x => [x, g[suffixField]].join("_"));
    }

    if (numberField != null) {
        // switch to 1-based indexing
        const rg = _.range(g[numberField]).map(x => x + 1);
        names = names.flatMap(n => rg.map(i => [n, i].join("_")));
    }

    return names.map(x => ({ name: x }));
}

function applyFilter(obj, val) {
    return obj && _.entries(obj).every(
        ([key, options]) => options.includes(val[key])
    );
}

function isVisible(field, g) {
    return applyFilter(field.visible, g);
}

function isRequired(field, g) {
    return applyFilter(field.required, g);
}

function isValid(field, g) {
    const value = g[field.key];
    if (field.multiple) {
        return value.length > 0;
    } else if (field.type === "text") {
        return !!value;
    } else {
        return value != null;
    }
}

function _cardValue(config) {
    const res = {};
    for (const field of config.fields) {
        const {multiple, key, value} = field;
        // Move to regular array
        res[key] = multiple ? Array.from(value || []) : value;
    }
    return res;
}

export function cardValue(config) {
    const g = _cardValue(config);
    const res = {type: config.type}
    for (const field of config.fields) {
        if (isVisible(field, g) && isValid(field, g)) {
            res[field.key] = g[field.key];
        }
    }
    const validated = config.fields.every(x => !isRequired(x, g) || isValid(x, g));
    return validated ? res : null;
}

export function Card(props) {
    const [store, setStore] = props.input;
    const globalValue = () => _cardValue(props);
    const otherCards = () => store.cards.toSpliced(props.index, 1);
    const names = () => props.metadata
        .concat(otherCards().flatMap(getOutputs))
        .map(x => x.name);
    const onClose = () => setStore("cards", otherCards());

    return <div class="bg-white w-full p-4">
        <span class="text-blue-800 text-xl font-semibold">{props.label}</span>
        <span onClick={onClose}
            class="text-red-800 hover:text-red-900 text-xl font-semibold float-right cursor-pointer">
            ✕
        </span>
        <div class="mt-2">
            <For each={props.fields}>
                {(widget, index) => {
                    return <AutoWidget
                        names={names()} input={props.input}
                        index={index()} cardIndex={props.index}
                        cardValue={_cardValue(props)}
                        {...widget} //TODO pass explicitly
                        visible={isVisible(widget, globalValue())}
                        required={isRequired(widget, globalValue())}
                        valid={isValid(widget, globalValue())}/>;
                }}
            </For>
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
