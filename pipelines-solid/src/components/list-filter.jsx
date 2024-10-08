import { For } from "solid-js";
import { Toggler } from "./toggler";

export function ListFilter(props) {
    const checkboxes = <For each={props.summary}>
        {value => {
            const label = String(value);
            return <label class="inline-flex items-center">
                <input class="form-checkbox" type="checkbox" value={value} checked/>
                <span class="ml-2">{label}</span>
            </label>;
        }}
    </For>;
    const listFilter = <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        {checkboxes}
    </div>;

    return <Toggler name={props.name}>
        {listFilter}
    </Toggler>;
}