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
    const valid = () => {
        const val = value()[props.key];
        if (props.multiple) {
            return val.length > 0;
        } else if (props.type === "text") {
            return !!val;
        } else {
            return val != null;
        }
    }

    const starClassList = () => ({
        "invisible": !required(),
        "text-red-800": !valid(),
        "text-blue-800": valid(),
    });

    const label = <label for={props.id + props.key} class={selectClass}>
        <span classList={starClassList()}>* </span><span>{props.label}</span>
    </label>

    let wdg;
    switch (props.widget) {
        case "select":
            const options = () => applyTemplate(props.options, defaults());
            const wdgProps = createOptions(options);
            wdg = <Select id={props.id + props.key} onChange={updateValue}
                multiple={props.multiple} class="mb-2" {...wdgProps}
                placeholder={props.placeholder} initialValue={init[props.key] || ""}
                required={required()}>
            </Select>;
            break;
        case "input":
            wdg = <Input id={props.id + props.key}
                onChange={ev => updateValue(ev.target.value)}
                class="w-full mb-2" type={props.type}
                value={init[props.key]} placeholder={props.placeholder}
                min={props.min} max={props.max} step={props.step}
                required={required()}>
            </Input>;
            break;
        default:
            console.log("widget not available");
    }
    return <Show when={visible()}>{label}{wdg}</Show>;
}