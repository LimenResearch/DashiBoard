const className =
  "pl-2 py-0.5 rounded border outline-none border-gray-200" +
  " ring-offset-2 focus:ring-2 focus:ring-gray-300";

type InputProps = {
  class?: string
  value?: string;
  placeholder?: string;
  onChange?: (e: Event) => void;
  id?: string;
  required?: boolean;
}

export function Input(props: InputProps) {
  return <input
    class={className + " " + (props.class ?? "")}
    value={props.value}
    placeholder={props.placeholder}
    onChange={props.onChange}></input>;
}
