function classList(danger: boolean, disabled: boolean) {
  const activePositive = !danger && !disabled;
  const activeNegative = danger && !disabled;
  return {
    "text-xl": true,
    "font-semibold": true,
    rounded: true,
    "text-left": true,
    "py-2": true,
    "px-4": true,
    "mr-4": true,
    "bg-opacity-75": true,
    "border-2": true,
    "border-transparent": true,
    "bg-blue-100": activePositive,
    "hover:bg-blue-200": activePositive,
    "text-blue-800": activePositive,
    "hover:text-blue-900": activePositive,
    "focus:border-blue-500": activePositive,
    "bg-red-100": activeNegative,
    "hover:bg-red-200": activeNegative,
    "text-red-800": activeNegative,
    "hover:text-red-900": activeNegative,
    "focus:border-red-500": activeNegative,
    "bg-gray-200": disabled,
    "text-gray-900": disabled,
  };
}

type ButtonProps = {
  onClick?: any;
  disabled?: boolean;
  danger?: boolean;
  children: any;
};

export function Button(props: ButtonProps) {
  return (
    <button
      onClick={props.onClick ?? (() => {})}
      disabled={props.disabled ?? false}
      class={classList(props.danger ?? false, props.disabled ?? false)}
    >
      {props.children}
    </button>
  );
}

type AProps = {
  onClick: any;
  disabled: boolean;
  danger?: boolean;
  download?: string;
  href: string;
  children: any[];
};

export function A(props: AProps) {
  return (
    <a
      href={props.href}
      download={props.download}
      class={classList(props.danger ?? false, props.disabled)}
    >
      {props.children}
    </a>
  );
}
