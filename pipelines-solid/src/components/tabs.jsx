import { createSignal } from "solid-js";

const headerClass = `text-blue-800 text-2xl font-semibold rounded mr-4 px-4 py-2
                     cursor-pointer hover:bg-gray-200`;

export function Tabs(props) {
    const [activeIndex, setActiveIndex] = createSignal(0);
    const keys = () => props.children.map(c => c.key);
    const values = () => props.children.map(c => c.value);
    const headers = <ul class="flex mb-12">
        <For each={keys()}>
            {(item, index) => <ul onClick={() => setActiveIndex(index())} class={headerClass}>{item}</ul>}
        </For>
    </ul>
    const bodies = <div>
        <For each={values()}>
            {(item, index) => <Show when={index() === activeIndex()}>{item}</Show>}
        </For>
    </div>

    return <>
        {headers}
        {bodies}
    </>;
}
