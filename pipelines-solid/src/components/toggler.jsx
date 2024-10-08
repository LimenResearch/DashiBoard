import { createSignal, Show } from "solid-js";

function classList(active) {
    return {
        "text-blue-800": true,
        "text-xl": true,
        "font-semibold": true,
        "border-b-2": !active,
        "border-gray-200": true,
        "hover:bg-gray-200": true,
        "w-full": true,
        "text-left": true,
    };
}

// TODO: reenable the `modified` option
export function Toggler(props) {
    const [active, setActive] = createSignal(false);
    const btn = <button
            classList={classList(active())}
            onClick={() => setActive(!active())}>
        <span class="pl-4 py-4 inline-block">{props.name}</span>
        <Show when={props.modified}>
            <span class="float-right p-4 inline-block hover:text-red-300">
                ⬤
            </span>
        </Show>
    </button>;
    const content = <Show when={active()}>
        <div class="p-4 bg-white rounded-b border-b-2">
            {props.children}
        </div>
    </Show>;

    return <div >
        {btn}
        {content}
    </div>;
}
