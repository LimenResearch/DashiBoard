function classList(danger: boolean, disabled: boolean) {
  const activePositive = !danger && !disabled;
  const activeNegative = danger && !disabled;
  return {
    "text-xl": true,
    "font-semibold": true,
    "rounded-sm": true,
    "text-left": true,
    "py-2": true,
    "px-4": true,
    "mr-4": true,
    "bg-opacity-75": true,
    "border-2": true,
    "border-transparent": true,
    "bg-accent": activePositive,
    "hover:bg-accent/70": activePositive,
    "text-primary": activePositive,
    "hover:text-primary": activePositive,
    "focus:border-ring": activePositive,
    "bg-destructive/10": activeNegative,
    "hover:bg-destructive/20": activeNegative,
    "text-destructive": activeNegative,
    "hover:text-destructive": activeNegative,
    "focus:border-destructive": activeNegative,
    "bg-secondary": disabled,
    "text-muted-foreground": disabled,
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
