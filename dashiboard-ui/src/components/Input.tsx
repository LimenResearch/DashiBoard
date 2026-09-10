const className =
  "pl-2 py-0.5 rounded-sm border outline-none border-border" +
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
