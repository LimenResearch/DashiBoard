import { createSignal, Show } from "solid-js";

function buttonClassList(active) {
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

function notificationClassList(modified) {
    return {
        "float-right": true,
        "p-4": true,
        "inline-block": true,
        "hover:text-red-300": true,
        "invisible": !modified,
    };
}

export function Toggler(props) {
    const [active, setActive] = createSignal(false);
    let notification;
    const onButtonClick = e => notification.isEqualNode(e.target) || setActive(!active());
    return <div>
        <button
            classList={buttonClassList(active())}
            onClick={onButtonClick}>
            <span class="pl-4 py-4 inline-block">{props.name}</span>
            <span ref={notification}
                    classList={notificationClassList(props.modified)}
                    onClick={props.onReset}>
                ⬤
            </span>
        </button>
        <Show when={active()}>
            <div class="p-4 bg-white rounded-b border-b-2">
                {props.children}
            </div>
        </Show>
    </div>;
}
