import { createSignal } from "solid-js";

function classList(submit) {
    return {
        "rounded"              : true,
        "py-2"                 : true,
        "px-4"                 : true,
        "text-2xl"             : true,
        "font-semibold"        : true,
        "text-blue-800"        : true,
        "hover:text-blue-900"  : true,
        "hover:bg-gray-200"    : !submit,
        "bg-blue-100"          : submit,
        "hover:bg-blue-200"    : submit,
        "border-2"             : submit,
        "border-transparent"   : submit,
        "focus:border-blue-500": submit,
    }
}

export function Tabs(props) {
    const [activeIndex, setActiveIndex] = createSignal(0);
    const keys = () => props.children.map(c => c.key);
    const values = () => props.children.map(c => c.value);
    
    return <>
        <div class="flex mb-12">
            <For each={keys()}>
                {(item, index) => <span
                        onClick={() => setActiveIndex(index())}
                        classList={classList(false)}>{item}</span>}
            </For>
            <button classList={classList(true)} onClick={props.onSubmit}>
                {props.submit}
            </button>
        </div>
        <div>
            <For each={values()}>
                {(item, index) => <Show when={index() === activeIndex()}>{item}</Show>}
            </For>
        </div>
    </>;
}
