// Height, not vertical padding. Stock shadcn controls are `h-10`; measured usage in the host is
// `h-7` (65 sites) and `h-8` (63) against `h-10` (16) — and inputs and selects get the same
// treatment as buttons, which is the part §3b's list left out.
const className =
  "h-7 px-2 text-xs rounded-sm border outline-none border-border" +
  " ring-offset-2 focus:ring-2 focus:ring-ring";

type InputProps = {
  type?: string;
  class?: string
  value?: string;
  placeholder?: string;
  id?: string;
  required?: boolean;
  min?: number;
  max?: number;
  step?: number;
  onChange?: (e: Event) => void;
};

export function Input(props: InputProps) {
  return <input
    type={props.type ?? "text"}
    class={className + " " + (props.class ?? "")}
    value={props.value}
    placeholder={props.placeholder}
    id={props.id}
    required={props.required}
    min={props.min}
    max={props.max}
    step={props.step}
    onChange={props.onChange}></input>;
}
