import { IntervalFilter } from "../components/interval-filter";
import { ListFilter } from "../components/list-filter";

export function Filters(props) {
    const intervalFilters = <For each={props.metadata.filter(x => x.type == "numerical")}>
        {IntervalFilter}
    </For>;
    const listFilters = <For each={props.metadata.filter(x => x.type == "categorical")}>
        {ListFilter}
    </For>;

    return <div class="flex flex-row gap-4">
        <div class="basis-1/2">{intervalFilters}</div>
        <div class="basis-1/2">{listFilters}</div>
    </div>;
}
