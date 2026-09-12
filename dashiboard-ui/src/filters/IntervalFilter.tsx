import { Input } from "../components/Input";
import { Toggler } from "../components/Toggler";
import { FILTERS_STORE, Interval } from "../stores";

// A numeric column's range, as two bounds.
//
// Still two fields rather than one range slider — see `01-decisions.md`; a slider is a separate
// decision, not a refactor of this one.

type IntervalFilterProps = {
  name: string;
  summary: { min: number; max: number; step?: number };
};

type Side = "min" | "max";

export function IntervalFilter(props: IntervalFilterProps) {
  const [state, setState] = FILTERS_STORE;

  const modified = () => state.numerical[props.name] != null;
  const value = () =>
    state.numerical[props.name] ?? new Interval(props.summary.min, props.summary.max);

  const setValue = (next: Interval | null) =>
    setState((draft) => {
      draft.numerical[props.name] = next;
    });

  /**
   * Bounds that cross select no rows at all — which looks like a column with no data rather than
   * like a mistake, since nothing downstream objects. The field says so instead.
   */
  const crossed = () => value().min > value().max;

  function update(raw: string, side: Side) {
    const parsed = Number.parseFloat(raw);
    // An empty or half-typed field parses to NaN. Writing that stores a bound nothing can compare
    // against and no reset short of the button clears, so the last good value stands instead.
    if (Number.isNaN(parsed)) return;
    const next = value().clone();
    next[side] = parsed;
    setValue(next);
  }

  return (
    <Toggler name={props.name} modified={modified()} onReset={() => setValue(null)}>
      <form class="flex items-center gap-2">
        <Input
          type="number"
          aria-label={`${props.name} lower bound`}
          class="w-full"
          invalid={crossed()}
          min={props.summary.min}
          max={props.summary.max}
          step={props.summary.step}
          value={value().min.toString()}
          onChange={(e) => update(e.currentTarget.value, "min")}
        />
        <span class="text-detail text-muted-foreground">to</span>
        <Input
          type="number"
          aria-label={`${props.name} upper bound`}
          class="w-full"
          invalid={crossed()}
          // Not `summary.min`: the upper field steps *down* from `max`, so the lowest value on its
          // grid is offset by however much the range fails to divide by the step. With min 0,
          // max 10, step 3 the reachable values are 1, 4, 7, 10 — so 1, not 0.
          min={
            props.summary.min +
            ((props.summary.max - props.summary.min) % (props.summary.step ?? 1))
          }
          max={props.summary.max}
          step={props.summary.step}
          value={value().max.toString()}
          onChange={(e) => update(e.currentTarget.value, "max")}
        />
      </form>
    </Toggler>
  );
}
