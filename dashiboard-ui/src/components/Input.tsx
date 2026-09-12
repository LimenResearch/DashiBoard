// The text field.
//
// Height, not vertical padding. Sizing a control by padding around a large font is what made our
// Button three times the size of its host's. The height itself is a token now rather than a
// literal, so a roomier host can resize this field through the same channel it repaints it — see
// the density block in App.css.
//
// It carries an `invalid` state because A7 gives it something to say. The probe addresses each
// failure by JSON Pointer, so a field can be told it is the offender; without a state to render,
// that information has nowhere to land but a banner above the page.

const BASE =
  "h-control-xs rounded-sm border px-2 text-control-xs outline-none ring-offset-2 focus:ring-2 focus:ring-ring";

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
