function classList(danger: boolean, disabled: boolean) {
  const activePositive = !danger && !disabled;
  const activeNegative = danger && !disabled;
  return {
    // Density per 05-nexus-weaver-brief §3b: the host sizes buttons by *height* (`h-7`/`h-8`)
    // with `text-xs` labels, not by padding around a large font. At `text-xl py-2 border-2` this
    // button was roughly three times its host's — and §3b's point is that density, not colour,
    // is what makes an embedded UI read as foreign.
    "text-xs": true,
    "font-semibold": true,
    "rounded-sm": true,
    "text-left": true,
    "inline-flex": true,
    "items-center": true,
    "h-7": true,
    "px-2.5": true,
    "mr-2": true,
    "border": true,
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
