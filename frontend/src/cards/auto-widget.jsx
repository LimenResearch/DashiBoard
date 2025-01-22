import { createOptions, Select } from "@thisbeyond/solid-select";
import { Input } from "../components/input";

const selectClass = "text-blue-800 font-semibold py-4 w-full text-left";

function applyFilter(obj, val) {
    return obj && Object.entries(obj).every(
        ([key, options]) => options.includes(val[key])
    );
}

function applyTemplate(obj, def) {
    const k = obj["-v"];
    return (k != null) ? def[k] : obj;
}

function parseNumber(s) {
    const x = parseFloat(s);
    return isNaN(x) ? null : x;
}

export function AutoWidget(props) {
    const [value, setter] = props.input;
    const init = value(); // No reactivity here
    const defaults = () => ({ names: props.names });
    const parse = x => (props.type === "number") ? parseNumber(x) : x;
    const parseAll = x => props.multiple ? x.map(parse) : parse(x);
    const updateValue = x => setter(props.key, parseAll(x));
    const visible = () => applyFilter(props.visible, value());
    const required = () => applyFilter(props.required, value());
    const label = () => required() ? props.label + " *" : props.label

    let wdg;
    switch (props.widget) {
        case "select":
            const options = () => applyTemplate(props.options, defaults());
            const wdgProps = createOptions(options);
            wdg = <>
                <label for={props.id + props.key} class={selectClass}>
                    {label()}
                </label>
                <Select id={props.id + props.key} onChange={updateValue}
                    multiple={props.multiple} class="mb-2" {...wdgProps}
                    placeholder={props.placeholder} initialValue={init[props.key] || ""}
                    required={required()}>
                </Select>
            </>;
            break;
        case "input":
            wdg = <>
                <label for={props.id + props.key} class={selectClass}>
                    {label()}
                </label>
                <Input id={props.id + props.key}
                    onChange={ev => updateValue(ev.target.value)}
                    class="w-full mb-2" type={props.type}
                    value={init[props.key]} placeholder={props.placeholder}
                    min={props.min} max={props.max} step={props.step}
                    required={required()}>
                </Input>
            </>;
            break;
        default:
            console.log("widget not available");
    }
    return <Show when={visible()}>{wdg}</Show>;
}