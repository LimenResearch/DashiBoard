import { onSettled, createEffect, omit } from "solid-js";
import Choices, { Options } from "choices.js";
import "choices.js/public/assets/styles/choices.min.css";

type ChoiceItem = {
  value: string;
  label: string;
  selected?: boolean;
  disabled?: boolean;
}

type ComboboxProps = {
  options: ChoiceItem[];
  value?: string | string[];
  multiple?: boolean;
  placeholder?: string;
  onChange?: (value: string | string[]) => void;
  id?: string;
  required?: boolean;
  addChoices?: boolean;
  addItems?: boolean;
}

// <Combobox
//   options={items}
//   multiple addItems addChoices
//   value={selected()}
//   onChange={(val) => setSelected(val)}
// />

export function Combobox(props: ComboboxProps) {
  let selectRef!: HTMLSelectElement;
  let choicesInstance: Choices | null = null;

  onSettled(() => {
    // 1. Initialize Choices.js
    choicesInstance = new Choices(selectRef, {
      placeholderValue: props.placeholder,
      removeItemButton: props.multiple ?? false,
      addChoices: props.addChoices,
      addItems: props.addItems
    });

    // 2. Listen to change events
    const handleChange = () => {
      if (!props.onChange || !choicesInstance) return;
      const val = choicesInstance.getValue(true);
      props.onChange(val);
    };

    selectRef.addEventListener("change", handleChange);

    // 3. Return cleanup function
    return () => {
      selectRef.removeEventListener("change", handleChange);
      choicesInstance?.destroy();
    };
  });

  // 4. Reactively update options when props.options changes
  createEffect(
    () => ({ options: props.options, value: props.value }),
    (signal: { options: ChoiceItem[], value?: string | string[]}) => {
      const { options, value } = signal;
      
      if (!choicesInstance) return;
      choicesInstance.clearStore();
      choicesInstance.setChoices(
        options.map((opt) => ({
          value: opt.value,
          label: opt.label,
          selected: Array.isArray(value)
            ? value.includes(opt.value)
            : value === opt.value,
          disabled: opt.disabled,
        })),
        "value",
        "label",
        true,
      );
    },
  );

  return <select ref={selectRef} multiple={props.multiple} id={props.id}  required={props.required} />;
}
