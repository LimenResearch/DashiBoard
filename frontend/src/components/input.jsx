const className =
  "pl-2 py-0.5 rounded border outline-none border-gray-200" +
  " ring-offset-2 focus:ring-2 focus:ring-gray-300";

export function Input(props) {
  return <input {...props} class={className + " " + props.class}></input>;
}
