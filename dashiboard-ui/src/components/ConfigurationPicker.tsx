import { For, Show } from "solid-js";
import { Button } from "./Button";

// A model or a training is a file in the workspace, chosen by name. The name alone says little,
// so the file is shown under the chooser, folded: what the configuration fixes — layers, loss,
// optimizer — against the settings it leaves open, which the branch below the picker draws.

type ConfigurationPickerProps = {
  id: string;
  /** `model` or `training`: the folder the names are the files of. */
  kind: string;
  options: string[];
  chosen: string | undefined;
  /** The text of the file behind a name, or `null` while it is not known. */
  text: (name: string) => string | null;
  onChoose: (name: string) => void;
  /** Ask the server for the files again — one was added by hand, say. */
  onRefresh: () => void;
};

export function ConfigurationPicker(props: ConfigurationPickerProps) {
  const unasked = () => props.chosen === undefined;
  const foreign = () => props.chosen !== undefined && !props.options.includes(props.chosen);
  // One name is not a question; it is still worth seeing what it holds.
  const lone = () => props.options.length === 1 && !foreign();
  const shown = () => (props.chosen === undefined ? null : props.text(props.chosen));
  return (
    <div class="flex flex-col gap-1">
      <div class="flex items-center gap-2">
        <Show when={!lone()} fallback={<span class="font-mono text-control-xs">{props.options[0]}</span>}>
          <select
            id={props.id}
            class={[
              "h-control-xs rounded-sm border px-2 text-control-xs",
              { "border-border": !unasked() && !foreign(), "border-warning": unasked() || foreign() },
            ]}
            value={props.chosen ?? ""}
            onChange={(event) => props.onChoose(event.currentTarget.value)}
          >
            <Show when={unasked()}>
              <option value="" disabled>choose…</option>
            </Show>
            <Show when={foreign()}>
              <option value={props.chosen} disabled>{props.chosen} — not available</option>
            </Show>
            <For each={props.options}>{(option) => <option value={option}>{option}</option>}</For>
          </select>
        </Show>
        <Button title={`ask the server for the ${props.kind} files again`} label={`refresh the ${props.kind} list`} onClick={props.onRefresh}>
          ↻
        </Button>
      </div>
      <Show when={shown()} keyed>
        {(text: string) => (
          <details data-configuration class="rounded-sm border border-border">
            <summary class="cursor-pointer px-2 py-1 font-mono text-control-xs text-muted-foreground">
              {props.chosen}.toml
            </summary>
            <pre class="overflow-x-auto px-2 py-1 font-mono text-control-xs whitespace-pre">{text}</pre>
          </details>
        )}
      </Show>
    </div>
  );
}
