import { For, Show } from "solid-js";
import { buttonClass } from "./Button";
import { Disclosure } from "./Disclosure";

// One value per column of a list — a transform for each input, say. A row per column, each with
// the values on offer; `identity` is the value of a column the map does not mention, so choosing
// it removes the entry rather than writing it.

const IDENTITY = "identity";

type MapFieldProps = {
  label: string;
  id: string;
  /** The list the columns belong to, as the author knows it: `inputs`. */
  listName: string;
  columns: string[];
  /** Entries naming a column the list no longer reaches. */
  stale: string[];
  values: (string | number)[];
  held: Record<string, string>;
  /** A column that cannot take a value — a categorical one cannot be transformed. */
  fixed: (column: string) => boolean;
  onChange: (next: Record<string, string> | undefined) => void;
};

export function MapField(props: MapFieldProps) {
  const write = (column: string, value: string | undefined) => {
    const { [column]: _, ...rest } = props.held;
    const next = value === undefined || value === IDENTITY ? rest : { ...rest, [column]: value };
    props.onChange(Object.keys(next).length > 0 ? next : undefined);
  };
  const selectClass = "h-control-xs rounded-sm border border-border px-2 text-control-xs";
  const rows = () => props.columns.length + props.stale.length;

  return (
    <Show when={props.values.length > 0 && rows() > 0}>
      <Disclosure summary={<span class="text-control-xs font-medium text-primary">{props.label}</span>}>
        <div id={props.id} class="my-1 flex flex-col gap-1">
          <For each={props.columns}>
            {(column) => (
              <div data-row={column} class="flex items-center gap-2">
                <span class="min-w-0 grow truncate font-mono text-control-xs">{column}</span>
                <Show
                  when={!props.fixed(column)}
                  fallback={<span class="text-control-xs text-muted-foreground italic">categorical</span>}
                >
                  <select
                    aria-label={`transform for ${column}`}
                    class={selectClass}
                    value={props.held[column] ?? IDENTITY}
                    onChange={(event) => write(column, event.currentTarget.value)}
                  >
                    <option value={IDENTITY}>{IDENTITY}</option>
                    <For each={props.values}>{(value) => <option value={String(value)}>{value}</option>}</For>
                  </select>
                </Show>
              </div>
            )}
          </For>
          {/* What the server will refuse, shown so it can be seen and cleared. */}
          <For each={props.stale}>
            {(column) => (
              <div data-row={column} data-stale class="flex items-center gap-2 text-warning">
                <span class="min-w-0 grow truncate font-mono text-control-xs">
                  {column} <span class="font-sans italic">— not among the {props.listName}</span>
                </span>
                <select aria-label={`transform for ${column}`} class={selectClass} disabled value={props.held[column]}>
                  <option value={props.held[column]}>{props.held[column]}</option>
                </select>
                <button
                  type="button"
                  aria-label={`remove the transform for ${column}`}
                  onClick={() => write(column, undefined)}
                  class={buttonClass("danger")}
                >
                  remove
                </button>
              </div>
            )}
          </For>
        </div>
      </Disclosure>
    </Show>
  );
}
