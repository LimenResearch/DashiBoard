import { createSignal, mergeProps } from "solid-js";
import { AutoWidget, initAutoWidget } from "./auto-widget";

export function getOutputs(config, content) {
    const { field, suffixField } = config.output;
    const suffix = suffixField ? content[suffixField] : null;
    const multiple = config.fields.find(x => x.key === field).multiple;
    const output = multiple ? content[field] : [content[field]];
    const names = suffix ? output.map(x => [x, suffix].join('_')) : output;
    return names.map(x => ({ name: x }));
}

function setKey([value, setValue], k, v) {
    const newValue = Object.assign({}, value());
    newValue[k] = v;
    setValue(newValue);
}

export function initCardContent(config) {
    const content = {};
    content.type = config.type;
    for (const { key, value } of config.fields) {
        content[key] = value;
    }
    const [value, setValue] = createSignal(content);
    const setter = (k, v) => setKey([value, setValue], k, v);
    const widgets = config.fields.map(x => initAutoWidget(x, value, setter));

    const input = widgets.map(x => x.input)
    const output = () => input.every(x => !x.required() || x.valid()) ? value() : null;

    return { input, output };
}

export function CardContent(props) {
    const names = () => props.metadata.map(x => x.name);
    const id = crypto.randomUUID();
    return <For each={props.input}>
        {widget => {
            return <AutoWidget id={id} names={names()} input={widget}></AutoWidget>
        }}
    </For>;
}
