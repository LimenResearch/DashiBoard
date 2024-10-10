import { For } from "solid-js";
import { Toggler } from "./toggler";

export function ListFilter(props) {
    const modified = () => props.store.numerical[props.name] != null
    const list = () => modified() ?
        props.store.numerical[props.name] :
        new Set(props.summary);
    const setList = value => props.setStore("numerical", { [props.name]: value });

    const onReset = () => setList(null);

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <For each={props.summary}>
                {value => {
                    const onClick = e => {
                        let newList = new Set(list());
                        e.target.checked ? newList.add(value) : newList.delete(value);
                        props.summary.every(x => newList.has(x)) && (newList = null);
                        setList(newList);
                    }
                    const label = String(value);
                    return <label class="inline-flex items-center">
                        <input class="form-checkbox" type="checkbox" value={value}
                            checked={list().has(value)} onClick={onClick} />
                        <span class="ml-2">{label}</span>
                    </label>;
                }}
            </For>
        </div>
    </Toggler>;
}
