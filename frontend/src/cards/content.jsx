import { createSignal } from "solid-js";
import { AutoWidget } from "./autoWidget";
import { CARD_CONFIGS } from "./configs"

function getConfig(type) {
    return CARD_CONFIGS.find(x => x.type === type);
}

export function getOutputs(content) {
    const { field, suffixField, multiple } =  getConfig(content.type).output;
    const suffix = suffixField ? content[suffixField] : null;
    const output = multiple ? content[field] : [content[field]];
    const names = suffix ? output.map(x => [x, suffix].join('_')) : output;
    return names.map(x => ({name: x}));
}

function setKey([value, setValue], k, v) {
    const newValue = Object.assign({}, value());
    newValue[k] = v;
    setValue(newValue);
}

export function cardContent(type) {
    const content = {};
    content.type = type;
    for (const v of getConfig(type).fields) {
        const {key, value} = v;
        content[key] = value;
    }
    return content;
}

export function initCardContent(type) {
    const init = cardContent(type);
    const [value, setValue] = createSignal(init);
    const setter = (k, v) => setKey([value, setValue], k, v);
    return { input: [value, setter], output: value };
}

export function CardContent(props) {
    const names = () => props.metadata.map(x => x.name);
    const id = crypto.randomUUID();
    return <For each={getConfig(props.type).fields}>
        {itemProps => {
            return <AutoWidget id={id} input={props.input}
                names={names()} {...itemProps}></AutoWidget>
        }}
    </For>;
}
