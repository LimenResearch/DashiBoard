import { For } from "solid-js";
import { Checkbox } from "../components/Checkbox";
import { Toggler } from "../components/Toggler";
import { FILTERS_STORE, List } from "../stores";

type ListFilterProps = {
  name: string;
  summary: unknown[];
};

export function ListFilter(props: ListFilterProps) {
  const [state, setState] = FILTERS_STORE;

  const modified = () => state.categorical[props.name] != null;
  const list = () => state.categorical[props.name] ?? new Set(props.summary);
  const setList = (value: List | null) =>
    setState((draft) => {
      draft.categorical[props.name] = value;
    });

  function updateValid(checked: boolean, value: unknown) {
    const next = new Set(list());
    if (checked) {
      next.add(value);
    } else {
      next.delete(value);
    }
    // Everything selected is the same as no filter, so it is stored as none rather than as a
    // list that happens to include every value.
    setList(props.summary.every((x) => next.has(x)) ? null : next);
  }

  const onReset = () => setList(null);

  return (
    <Toggler name={props.name} modified={modified()} onReset={onReset}>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
        <For each={props.summary}>
          {(value) => (
            <Checkbox
              label={String(value)}
              checked={list().has(value)}
              onChange={(checked) => updateValid(checked, value)}
            />
          )}
        </For>
      </div>
    </Toggler>
  );
}
