// Solid 2 exports the element type directly; `JSX.Element` is the Solid 1 namespace
// idiom and no longer resolves. Aliased so it does not read as the DOM's global `Element`.
import type { Element as JSXElement } from "solid-js";

// The button, as a design-system component rather than as one page's button.
//
// Three things changed when it became something to publish. It names its variants instead of
// carrying a `danger` boolean, because a flag does not extend to a third option and a system's
// card has to read "default / danger, two sizes". It sizes by *height*, and the heights are the
// shared `--control-height-*` steps rather than literals — nexus-weaver left their own Button
// untokenised because its ladder runs h-5 to h-11 and does not map onto three steps; ours has two
// sizes that land exactly on `xs` and `sm`, which is why the same call is right here and wrong
// there. And it brings no margin of its own: a component that positions itself is right in the one
// place it was written for and wrong everywhere else.

export type ButtonVariant = "default" | "danger";
export type ButtonSize = "sm" | "md";

// C8: keyed on the union, never on `string`. Adding a variant fails the build rather than
// resolving to `undefined` and rendering an unstyled control.
const VARIANTS: Record<ButtonVariant, string> = {
  default: "bg-accent text-accent-foreground hover:bg-accent/70 focus:border-ring",
  danger: "bg-destructive/10 text-destructive hover:bg-destructive/20 focus:border-destructive",
};

const SIZES: Record<ButtonSize, string> = {
  sm: "h-control-xs px-2.5",
  md: "h-control-sm px-3",
};

const DISABLED = "bg-secondary text-muted-foreground";

function className(variant: ButtonVariant, size: ButtonSize, disabled: boolean) {
  return [
    "inline-flex items-center rounded-sm border border-transparent text-control-xs font-semibold",
    SIZES[size],
    disabled ? DISABLED : VARIANTS[variant],
  ].join(" ");
}

type ButtonProps = {
  /** Receives the event, because a button inside a `<summary>` has to stop it toggling the
   *  disclosure. Handlers that ignore it stay assignable. */
  onClick?: (event: MouseEvent) => void;
  disabled?: boolean;
  variant?: ButtonVariant;
  size?: ButtonSize;
  children: JSXElement;
};

export function Button(props: ButtonProps) {
  return (
    <button
      onClick={(event) => props.onClick?.(event)}
      disabled={props.disabled ?? false}
      class={className(props.variant ?? "default", props.size ?? "sm", props.disabled ?? false)}
    >
      {props.children}
    </button>
  );
}

type AProps = {
  disabled?: boolean;
  variant?: ButtonVariant;
  size?: ButtonSize;
  download?: string;
  href: string;
  children: JSXElement;
};

/** A link that reads as a button. Same surface, so the two cannot drift apart visually. */
export function A(props: AProps) {
  return (
    <a
      href={props.href}
      download={props.download}
      class={className(props.variant ?? "default", props.size ?? "sm", props.disabled ?? false)}
    >
      {props.children}
    </a>
  );
}
