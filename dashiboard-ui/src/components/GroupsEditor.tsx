import { createSignal, For, Show } from "solid-js";

import { Button } from "./Button";
import { SelectorField, type SelectorItem } from "./SelectorField";
import { CARDS_STORE, addGroup, removeGroup, renameGroup, setGroup, type Selector } from "../stores";
import { withoutOption, type Defs, type IRNode } from "../ir";

// Authoring `[groups]` — §6's "one picker, two levels".
//
// A group *is* a list of selector items, the same shape a card's `inputs` holds, so this reuses
// `SelectorField` rather than describing the vocabulary a second time. That is not a convenience:
// a group may name cols, other groups and nodes (measured), so a purpose-built control here would
// have to reimplement the whole picker and would drift from it.
//
// Until a group exists, every picker's `groups` tab is empty by construction — which is what made
// this the hole worth closing next.

export function GroupsEditor(props: { defs: Defs }) {
  const [state] = CARDS_STORE;
  const [error, setError] = createSignal<string | null>(null);

  // The `$defs/variable` node: one item of a selector list, which is exactly what a group holds.
  const itemNode = () => (props.defs.variable ?? {}) as IRNode;

  function rename(from: string, field: HTMLInputElement) {
    const to = field.value.trim();
    if (renameGroup(from, to)) {
      setError(null);
      return;
    }
    // The document refused, so the screen must not keep showing the name that was typed.
    field.value = from;
    setError(to === "" ? "A group needs a name." : `There is already a group called "${to}".`);
  }

  return (
    <div>
      <div class="flex items-center gap-3 p-4">
        <span class="text-sm font-semibold text-blue-800">Groups</span>
        <Button onClick={() => void addGroup()}>Add group</Button>
      </div>

      <Show when={error()}>
        <p class="mx-4 mb-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-800">
          {error()}
        </p>
      </Show>

      <Show
        when={Object.keys(state.groups).length > 0}
        fallback={
          <p class="px-4 text-sm text-gray-500">
            No groups defined. A group names a set of columns once, so several cards can refer to
            it — and nothing can refer to one until it exists.
          </p>
        }
      >
        <For each={Object.keys(state.groups)}>
          {(name) => (
            <div class="my-4 rounded border border-gray-200 p-4">
              <div class="mb-2 flex items-center justify-between gap-3">
                <input
                  class="rounded border border-gray-200 px-2 py-0.5 font-mono text-sm"
                  aria-label="group name"
                  value={name}
                  // `change`, not `input`: renaming on every keystroke would rewrite the document
                  // once per character, and each rewrite is a name other cards may be referring to.
                  onChange={(event) => rename(name, event.currentTarget)}
                />
                <Button danger onClick={() => removeGroup(name)}>
                  Remove
                </Button>
              </div>
              <SelectorField
                itemNode={itemNode()}
                // A group naming itself is a loop — measured, and rejected as one — so its own
                // name is not on offer inside it.
                defs={withoutOption(props.defs, "group", name)}
                label={name}
                value={state.groups[name]}
                onChange={(items: SelectorItem[]) => setGroup(name, items as Selector[])}
              />
            </div>
          )}
        </For>
      </Show>
    </div>
  );
}
