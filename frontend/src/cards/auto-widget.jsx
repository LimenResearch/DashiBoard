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

export function initAutoWidget(props, value, setter) {
    const init = value()[props.key]; // No reactivity here

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

    const input = {
        widget: props.widget,
        key: props.key,
        label: props.label,
        placeholder: props.placeholder,
        init: init,
        min: props.min,
        max: props.max,
        step: props.step,
        options: props.options,
        multiple: props.multiple,
        type: props.type,
        visible: visible,
        required: required,
        id: props.id,
        valid: valid,
        updateValue: updateValue,
    };

    const output = {};

    return { input, output };
}

export function AutoWidget(props) {
    const { widget, key, label, placeholder, init, min, max, step, options,
        multiple, type, visible, required, id, valid, updateValue } = props.input

    const starClassList = () => ({
        "invisible": !required(),
        "text-red-800": !valid(),
        "text-blue-800": valid(),
    });

    const defaults = () => ({ names: props.names });

    const labelWidget = <label for={id + key} class={selectClass}>
        <span classList={starClassList()}>* </span><span>{label}</span>
    </label>

    let inputWidget;
    switch (widget) {
        case "select":
            const wdgProps = createOptions(() => applyTemplate(options, defaults()));
            inputWidget = <Select id={id + key} onChange={updateValue}
                multiple={multiple} class="mb-2" {...wdgProps}
                placeholder={placeholder} initialValue={init || ""}
                required={required()}>
            </Select>;
            break;
        case "input":
            inputWidget = <Input id={id + key}
                onChange={ev => updateValue(ev.target.value)}
                class="w-full mb-2" type={type}
                value={init} placeholder={placeholder}
                min={min} max={max} step={step}
                required={required()}>
            </Input>;
            break;
        default:
            throw new Error("widget not available");
    }
    return <Show when={visible()}>{labelWidget}{inputWidget}</Show>;
}