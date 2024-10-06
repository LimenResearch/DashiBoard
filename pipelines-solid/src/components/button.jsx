function classList(positive) {
    return {
        "text-xl": true,
        "font-semibold": true,
        "rounded": true,
        "text-left": true,
        "py-2": true,
        "px-4": true,
        "mr-4": true,
        "bg-opacity-75": true,
        "border-2": true,
        "border-transparent": true,
        "bg-blue-100": positive,
        "hover:bg-blue-200": positive,
        "text-blue-800": positive,
        "hover:text-blue-900": positive,
        "focus:border-blue-500": positive,
        "bg-red-100": !positive,
        "hover:bg-red-200": !positive,
        "text-red-800": !positive,
        "hover:text-red-900": !positive,
        "focus:border-red-500": !positive,
    }
}

export function Button(props) {
    return <button onClick={props.onClick} classList={classList(props.positive)}>
        {props.children}
    </button>;
}
