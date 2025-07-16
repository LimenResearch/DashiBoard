import { createSignal, Show } from "solid-js";

function classList(active, submit) {
  return {
    rounded: true,
    "py-2": true,
    "px-4": true,
    "text-2xl": true,
    "font-semibold": true,
    "text-blue-800": !active,
    "hover:text-blue-900": !active,
    "text-blue-900": active,
    "bg-gray-200": active,
    "hover:bg-gray-200": !submit && !active,
    "bg-blue-100": submit,
    "hover:bg-blue-200": submit,
    "border-2": submit,
    "border-transparent": submit,
    "focus:border-blue-500": submit,
  };
}

export function Tabs(props) {
  const [activeIndex, setActiveIndex] = createSignal(0);
  const keys = () => props.children.map((c) => c.key);
  const values = () => props.children.map((c) => c.value);

  return (
    <>
      <div class="flex mb-12">
        <For each={keys()}>
          {(item, index) => (
            <button
              onClick={() => setActiveIndex(index())}
              classList={classList(activeIndex() === index(), false)}
            >
              {item}
            </button>
          )}
        </For>
        <Show when={props.submit}>
          <button classList={classList(false, true)} onClick={props.onSubmit}>
            {props.submit}
          </button>
        </Show>
      </div>
      <div>
        <For each={values()}>
          {(item, index) => (
            <Show when={index() === activeIndex()}>{item}</Show>
          )}
        </For>
      </div>
    </>
  );
}
