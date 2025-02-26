import * as _ from "lodash"
import { createSignal } from "solid-js";
import { AutoWidget, initAutoWidget } from "./auto-widget";

export function getOutputs(config, content) {
    const { field, suffixField, numberField } = config.output;
    const multiple = config.fields.find(x => x.key === field).multiple;

    let names = multiple ? content[field] : [content[field]];
    // interpret null option as empty list
    names = names || [];

    if (suffixField != null) {
        const suffix = content[suffixField];
        names = names.map(x => [x, suffix].join("_"));
    }

    if (numberField != null) {
        const number = content[numberField];
        const rg = _.range(number).map(x => x + 1); // switch to 1-based indexing
        names = names.flatMap(n => rg.map(i => [n, i].join("_")));
    }

    return names.map(x => ({ name: x }));
}

export function initCardContent(config) {
    const content = {};
    content.type = config.type;
    for (const { key, value } of config.fields) {
        content[key] = value;
    }
    const [value, setValue] = createSignal(content);
    const setter = (k, v) => setValue(_.assign({}, value(), {[k]: v}));
    const widgets = config.fields.map(x => initAutoWidget(x, value, setter));

    const input = widgets.map(x => x.input);
    const widgetOutputs = widgets.map(x => x.output);
    const validated = () => widgetOutputs.every(x => !x.required() || x.valid());
    const outputValue = () => {
        const val = value();
        const pairs = widgetOutputs
            .filter(x => x.visible() && x.valid()) // should we keep invalid fields?
            .map(x => [x.key, val[x.key]]);
        const res = {type: val.type};
        for (const [k, v] of pairs) {
            res[k] = v;
        }
        return res;
    }
    const output = { value: outputValue, validated };

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
