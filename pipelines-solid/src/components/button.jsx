function classList(positive, disabled) {
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
        "bg-blue-100": positive && !disabled,
        "hover:bg-blue-200": positive && !disabled,
        "text-blue-800": positive && !disabled,
        "hover:text-blue-900": positive && !disabled,
        "focus:border-blue-500": positive && !disabled,
        "bg-red-100": !positive && !disabled,
        "hover:bg-red-200": !positive && !disabled,
        "text-red-800": !positive && !disabled,
        "hover:text-red-900": !positive && !disabled,
        "focus:border-red-500": !positive && !disabled,
        "bg-gray-100": disabled,
        "text-gray-800": disabled,
        "focus:border-gray-500": disabled,
    }
}

export function Button(props) {
    const disabled = () => (props.disabled != null) && props.disabled;
    const positive = () => props.positive;
    return <button
            onClick={props.onClick}
            disabled={disabled()}
            classList={classList(positive(), disabled())}>
        {props.children}
    </button>;
}
