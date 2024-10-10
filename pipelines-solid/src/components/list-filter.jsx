import { createSignal, For } from "solid-js";
import { Toggler } from "./toggler";

function hasValue(x) {
    return Object.keys(x).some(k => x[k]);
}

export function ListFilter(props) {
    const [excluded, setExcluded] = createSignal({});

    const onReset = () => setExcluded({});

    const checkboxes = <For each={props.summary}>
        {value => {
            const onClick = e => setExcluded(Object.assign({}, excluded(), {[value]: !e.target.checked}));
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

    return <Toggler name={props.name} modified={hasValue(excluded())} onReset={onReset}>
        {listFilter}
    </Toggler>;
}
