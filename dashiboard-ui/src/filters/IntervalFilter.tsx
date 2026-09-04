import { Input } from "../components/Input";
import { Toggler } from "../components/Toggler";
import { filters_store, Interval } from "../root";

type IntervalFilterProps = {
  name: string;
  summary: { min: number; max: number; step?: number };
};

type Sides = "min" | "max";

export function IntervalFilter(props: IntervalFilterProps) {
  const { state, setState } = filters_store;

  const modified = () => state.numerical[props.name] != null;
  const filterValue = () =>
    state.numerical[props.name] ??
    new Interval(props.summary.min, props.summary.max);

  const setFilterValue = (value: Interval | null) =>
    setState((draft) => {
      draft.numerical[props.name] = value;
    });

  function updateValid(input: string, k: Sides) {
    let interval = filterValue().clone();
    interval[k] = parseFloat(input);
    setFilterValue(interval);
  }
  
  function updateTarget(e: Event, key: Sides) {
    if (e.target) {
      const target = e.target as HTMLInputElement;
      updateValid(target.value, key);
    }
  }

  const onReset = () => setFilterValue(null);

  const leftInput = (
    <Input
      type="number"
      min={props.summary.min}
      max={props.summary.max}
      step={props.summary.step}
      value={filterValue().min.toString()}
      onChange={(e: Event) => updateTarget(e, "min")}
    ></Input>
  );

  const rightInput = (
    <Input
      type="number"
      min={
        props.summary.min +
        ((props.summary.max - props.summary.min) % (props.summary.step ?? 1))
      }
      max={props.summary.max}
      step={props.summary.step}
      value={filterValue().max.toString()}
      onChange={(e: Event) => updateTarget(e, "max")}
    ></Input>
  );

  const filterForm = (
    <form class="flex justify-between">
      {leftInput}
      {rightInput}
    </form>
  );

  return (
    <Toggler name={props.name} modified={modified()} onReset={onReset}>
      {filterForm}
    </Toggler>
  );
}
