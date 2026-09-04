import { Combobox } from "@kobalte/core";

export function BasicExample() {
  return (
    <Combobox
      options={ALL_STRING_OPTIONS}
      placeholder="Search a fruit…"
      itemComponent={(props) => (
        <Combobox.Item item={props.item} class={style.combobox__item}>
          <Combobox.ItemLabel>{props.item.rawValue}</Combobox.ItemLabel>
          <Combobox.ItemIndicator class={style["combobox__item-indicator"]}>
            <CheckIcon />
          </Combobox.ItemIndicator>
        </Combobox.Item>
      )}
    >
      <Combobox.Control class={style.combobox__control} aria-label="Fruit">
        <Combobox.Input class={style.combobox__input} />
        <Combobox.Trigger class={style.combobox__trigger}>
          <Combobox.Icon class={style.combobox__icon}>
            <CaretSortIcon />
          </Combobox.Icon>
        </Combobox.Trigger>
      </Combobox.Control>
      <Combobox.Portal>
        <Combobox.Content class={style.combobox__content}>
          <Combobox.Listbox class={style.combobox__listbox} />
        </Combobox.Content>
      </Combobox.Portal>
    </Combobox>
  );
}

