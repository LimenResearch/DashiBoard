import { createSignal, For, Show } from "solid-js";

import { Button } from "./Button";
import { Disclosure, summaryAction } from "./Disclosure";
import { SelectorField } from "./SelectorField";
import type { SelectorItem } from "../selector";
import {
  CARDS_STORE,
  addGroup,
  confirmDefinition,
  isConfirmed,
  removeGroup,
  renameGroup,
  setGroup,
  type Selector,
} from "../stores";
import { checkGroup, type Incompleteness } from "../completeness";
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
  // What Confirm found last time it was pressed, per group. Not run continuously — the step exists
  // so the author says when they are done, not so a panel argues while they type.
  const [unfinished, setUnfinished] = createSignal<Record<string, Incompleteness[]>>({});
  const confirmed = (name: string) => isConfirmed(`group:${name}`, state.groups[name]);

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
      <div class="flex items-center gap-2 p-3">
        <span class="text-control-xs font-semibold text-primary">Groups</span>
        <Button onClick={() => void addGroup()}>Add group</Button>
      </div>

      <Show when={error()}>
        <p class="mx-4 mb-2 rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-control-xs text-destructive">
          {error()}
        </p>
      </Show>

      <Show
        when={Object.keys(state.groups).length > 0}
        fallback={
          <p class="px-4 text-control-xs text-muted-foreground">
            No groups defined. A group names a set of columns once, so several cards can refer to
            it — and nothing can refer to one until it exists.
          </p>
        }
      >
        <For each={Object.keys(state.groups)}>
          {(name) => (
            <div class="my-2 rounded-sm border border-border p-2">
              <Disclosure
                bodyClass="mt-2 flex flex-col gap-1 border-t border-border pt-2"
                summary={
                  <>
                    {/* Folded, this is the whole group: the key it is referred to by, and its
                        name. A pipeline with six groups should read as six lines. */}
                    <span class="text-control-xs font-semibold text-primary">name</span>
                    <span class="text-muted-foreground">:</span>
                    <span class="font-mono text-control-xs">{name}</span>
                    <span
                      aria-label={confirmed(name) ? "confirmed" : "not confirmed"}
                      title={confirmed(name) ? "confirmed" : "not confirmed"}
                      class={[
                        "ml-1 h-2 w-2 shrink-0 rounded-full",
                        {
                          "bg-success": confirmed(name),
                          "border border-muted-foreground": !confirmed(name),
                        },
                      ]}
                    />
                    <span class="ml-auto flex items-center gap-2">
                      {/*
                        Unwired, deliberately — placed now so its position can be judged, with the
                        behaviour still to be designed. The distinction it will carry is
                        *completeness*, not validity: an empty group passes schema validation
                        (measured — `weather = []` constructs), and is still not something anyone
                        meant to define. So Confirm cannot simply run the validator; the validator
                        says yes.
                      */}
                      <Button
                        title="mark this group deliberately finished"
                        onClick={summaryAction(() => {
                          const found = checkGroup(state.groups[name] ?? []);
                          setUnfinished({ ...unfinished(), [name]: found });
                          if (found.length === 0) confirmDefinition(`group:${name}`, state.groups[name]);
                        })}
                      >
                        Confirm
                      </Button>
                      <Button variant="danger" onClick={summaryAction(() => removeGroup(name))}>
                        Remove
                      </Button>
                    </span>
                  </>
                }
              >
                {/* Warning rather than destructive: an empty group is legal and would run. It
                    would simply select nothing, which the schema has no way to say. */}
                <For each={unfinished()[name] ?? []}>
                  {(finding: Incompleteness) => (
                    <p class="rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground">
                      {finding.message}
                    </p>
                  )}
                </For>
                <div class="flex items-center gap-2">
                  <label
                    for={`group-name-${name}`}
                    class="w-32 shrink-0 text-control-xs font-semibold text-primary"
                  >
                    name
                  </label>
                  <input
                    id={`group-name-${name}`}
                    class="h-control-xs rounded-sm border border-border px-2 font-mono text-control-xs"
                    aria-label="group name"
                    value={name}
                    // `change`, not `input`: renaming on every keystroke would rewrite the document
                    // once per character, and each rewrite is a name other cards may be referring to.
                    onChange={(event) => rename(name, event.currentTarget)}
                  />
                </div>
                <SelectorField
                  itemNode={itemNode()}
                  // A group naming itself is a loop — measured, and rejected as one — so its
                  // own name is not on offer inside it.
                  defs={withoutOption(props.defs, "group", name)}
                  label={name}
                  value={state.groups[name]}
                  onChange={(items: SelectorItem[]) => setGroup(name, items as Selector[])}
                />
              </Disclosure>
            </div>
          )}
        </For>
      </Show>
    </div>
  );
}
