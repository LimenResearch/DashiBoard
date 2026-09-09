import { For } from "solid-js";
import { Toggler } from "../components/Toggler";
import { filters_store, List } from "../root";

type ListFilterProps = {
  name: string;
  summary: any[];
};

export function ListFilter(props: ListFilterProps) {
  const { state, setState } = filters_store;

  const modified = () => state.categorical[props.name] != null;
  const list = () => state.categorical[props.name] ?? new Set(props.summary);
  const setList = (value: List | null) => setState(draft => {draft.categorical[props.name] = value});

  function updateValid(checked: boolean, value: any) {
    let newList: Set<any> = new Set(list());
    checked ? newList.add(value) : newList.delete(value);
    setList(props.summary.every((x) => newList.has(x)) ? null : newList);
  };
  
  function updateTarget(e: Event, value: any) {
    if (e.target) {
      const target = e.target as HTMLInputElement;
      updateValid(target.checked, value);
    }
  }
  
  const onReset = () => setList(null);
  
  return (
    <Toggler name={props.name} modified={modified()} onReset={onReset}>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <For each={props.summary}>
          {(value) => {
            const onClick = (e: Event) => updateTarget(e, value);
            const label = String(value);
            return (
              <label class="inline-flex items-center">
                <input
                  class="form-checkbox"
                  type="checkbox"
                  value={value}
                  checked={list().has(value)}
                  onClick={onClick}
                />
                <span class="ml-2">{label}</span>
              </label>
            );
          }}
        </For>
      </div>
    </Toggler>
  );
}
