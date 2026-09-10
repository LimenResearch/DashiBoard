// The text field.
//
// Height, not vertical padding: stock shadcn controls are `h-10`, and measured usage in the host
// is `h-7` (65 sites) and `h-8` (63) against `h-10` (16). Inputs and selects take the same
// treatment as buttons — the part §3b's list left out, and the single biggest tell that an
// embedded UI is foreign.
//
// It carries an `invalid` state because A7 gives it something to say. The probe addresses each
// failure by JSON Pointer, so a field can be told it is the offender; without a state to render,
// that information has nowhere to land but a banner above the page.

const BASE =
  "h-7 rounded-sm border px-2 text-xs outline-none ring-offset-2 focus:ring-2 focus:ring-ring";

type InputProps = {
  type?: string;
  class?: string;
  value?: string;
  placeholder?: string;
  id?: string;
  required?: boolean;
  disabled?: boolean;
  /** Marks the field as the offender, for both sighted users and assistive tech. */
  invalid?: boolean;
  min?: number;
  max?: number;
  step?: number;
  "aria-label"?: string;
  onChange?: (e: Event & { currentTarget: HTMLInputElement }) => void;
};

export function Input(props: InputProps) {
  return (
    <input
      type={props.type ?? "text"}
      // Solid 2's `class` takes arrays and objects directly; building the string by hand re-runs
      // the whole expression on every change.
      class={[
        BASE,
        {
          "border-destructive text-destructive": props.invalid === true,
          "border-border": props.invalid !== true,
        },
        props.class ?? "",
      ]}
      value={props.value}
      placeholder={props.placeholder}
      id={props.id}
      required={props.required}
      disabled={props.disabled ?? false}
      aria-invalid={props.invalid === true ? "true" : "false"}
      aria-label={props["aria-label"]}
      min={props.min}
      max={props.max}
      step={props.step}
      // Wrapped rather than bound directly: an event handler on a native element is not reactive
      // the way other JSX props are, so a direct binding captures the first value of the prop.
      onChange={(e) => props.onChange?.(e)}
    />
  );
}
