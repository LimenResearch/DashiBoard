import { For, useContext } from "solid-js";
import { Toggler } from "../components/toggler";
import { FiltersContext } from "../create";

export function ListFilter(props) {
    const {state, setState} = useContext(FiltersContext);

    const modified = () => state.categorical[props.name] != null
    const list = () => modified() ?
        state.categorical[props.name] :
        new Set(props.summary);
    const setList = value => setState("categorical", { [props.name]: value });

    const onReset = () => setList(null);

    const update = (value, checked) => {
        let newList = new Set(list());
        checked ? newList.add(value) : newList.delete(value);
        props.summary.every(x => newList.has(x)) && (newList = null);
        setList(newList);
    }

    return <Toggler name={props.name} modified={modified()} onReset={onReset}>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <For each={props.summary}>
                {value => {
                    const onClick = e => update(value, e.target.checked);
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
