import * as _ from "lodash"
import { createOptions, Select } from "@thisbeyond/solid-select";
import { Input } from "../components/input";

const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";

function applyTemplate(obj, def) {
    const k = obj["-v"];
    return (k != null) ? def[k] : obj;
}

function parseNumber(s) {
    const x = parseFloat(s);
    return isNaN(x) ? null : x;
}

export function AutoWidget(props) {
    const [store, setStore] = props.input
    const parse = x => (props.type === "number") ? parseNumber(x) : x;
    const parseAll = x => props.multiple ? x.map(parse) : parse(x);
    const updateValue = x => setStore(
        "cards",
        props.cardIndex,
        "fields",
        props.index,
        {value: parseAll(x)}
    );

    const starClassList = () => ({
        "invisible": !props.required,
        "text-red-800": !props.valid,
        "text-blue-800": props.valid,
    });

    const defaults = () => ({ names: props.names });
    const id = _.uniqueId(props.key + "_");

    const labelWidget = <label for={id} class={selectClass}>
        <span classList={starClassList()}>* </span><span>{props.label}</span>
    </label>

    let inputWidget;
    switch (props.widget) {
        case "select":
            const wdgProps = createOptions(() => applyTemplate(props.options, defaults()));
            const initialValue = props.value || (props.multiple ? [] : "");
            inputWidget = <Select id={id}
                multiple={props.multiple}
                class="mb-2" {...wdgProps}
                placeholder={props.placeholder}
                initialValue={initialValue}
                onChange={updateValue}
                required={props.required}>
            </Select>;
            break;
        case "input":
            const value = props.value || ""; // avoid recursion
            inputWidget = <Input id={id}
                onChange={ev => updateValue(ev.target.value)}
                class="w-full mb-2" type={props.type}
                value={value} placeholder={props.placeholder}
                min={props.min} max={props.max} step={props.step}
                required={props.required}>
            </Input>;
            break;
        default:
            throw new Error("widget not available");
    }
    return <Show when={props.visible}>{labelWidget}{inputWidget}</Show>;
}