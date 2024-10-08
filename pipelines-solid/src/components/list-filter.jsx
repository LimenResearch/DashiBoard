import { createSignal, For } from "solid-js";
import { Toggler } from "./toggler";

function set(a, key, value) {
    const b = Object.assign({}, a);
    b[key] = value;
    return b;
}

export function ListFilter(props) {
    const [excluded, setExcluded] = createSignal({});

    const onReset = () => setExcluded({});
    const modified = () => Object.keys(excluded()).length > 0;

    const checkboxes = <For each={props.summary}>
        {value => {
            const onClick = e => setExcluded(set(excluded(), value, !e.target.checked));
            const checked = () => !(excluded()[value]);
            const label = String(value);
            return <label class="inline-flex items-center">
                <input class="form-checkbox" type="checkbox" value={value}
                    checked={checked()}  onClick={onClick}/>
                <span class="ml-2">{label}</span>
            </label>;
        }}
    </For>;
    const listFilter = <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        {checkboxes}
    </div>;

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        {listFilter}
    </Toggler>;
}