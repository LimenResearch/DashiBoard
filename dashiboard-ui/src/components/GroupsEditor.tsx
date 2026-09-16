import { createSignal, For, Show } from "solid-js";

import { Button } from "./Button";
import { Disclosure, summaryAction } from "./Disclosure";
import { SelectorField } from "./SelectorField";
import type { SelectorItem } from "../selector";
import {
  CARDS_STORE,
  PROBE_STORE,
  addGroup,
  confirmDefinition,
  isConfirmed,
  issuesForGroup,
  removeGroup,
  renameGroup,
  setGroup,
  type CardsStore,
  type Selector,
} from "../stores";
import { askProbe } from "../probe";
import type { Incompleteness } from "../completeness";
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
  const [probe] = PROBE_STORE;
  const [error, setError] = createSignal<string | null>(null);
  // What Confirm found last time it was pressed, per group. Not run continuously — the step exists
  // so the author says when they are done, not so a panel argues while they type.
  const [unfinished, setUnfinished] = createSignal<Record<string, Incompleteness[]>>({});
  const confirmed = (name: string) => isConfirmed(`group:${name}`, state.groups[name]);

  /**
   * The continuous probe's own opinion of this group, right now — not only what the last Confirm
   * captured. A stored confirmation was made against the document as it was then; the server is
   * the authority on what is true of it now, so a live error must not be outranked by an older
   * mark. A warning does not count: it renders live in the body already and was never something
   * Confirm refused over.
   */
  const liveError = (name: string) =>
    issuesForGroup(probe.issues, name).some((issue) => issue.severity !== "warning");

  /** unconfirmed · incomplete · confirmed — folded, the dot is the only thing on screen. */
  const groupState = (name: string) =>
    (unfinished()[name]?.length ?? 0) > 0 || liveError(name)
      ? "incomplete"
      : confirmed(name)
        ? "confirmed"
        : "unconfirmed";

  // The `$defs/variable` node: one item of a selector list, which is exactly what a group holds.
  const itemNode = () => (props.defs.variable ?? {}) as IRNode;

  /**
   * What the last Confirm found, minus whatever the continuous probe already shows live.
   *
   * Both lists can carry the same finding — Confirm's own `askProbe` answer and `PROBE_STORE`
   * (fed by the continuous probe, and by a failed run's issues via `reportRunIssues`) are two
   * independent askings of the same question, and the server's empty-group message doesn't stop
   * existing just because it was asked for twice. Filtering by message rather than merging the
   * lists keeps this the *fallback* — an item the live list cannot see yet renders here still.
   */
  const staleFindings = (name: string) => {
    const live = issuesForGroup(probe.issues, name).map((issue) => issue.message);
    return (unfinished()[name] ?? []).filter((finding) => !live.includes(finding.message));
  };

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
                        name. A pipeline with six groups should read as six lines. A long group
                        name used to push Confirm/Remove past the pane's edge.
                        `text-overflow: ellipsis` only renders in a block/inline formatting context
                        — on a flex box `overflow:hidden` just hard-clips a child mid-character —
                        so `truncate` lives on the inner, non-flex `data-group-text` span around the
                        text run, not on this flex wrapper. The full text still reaches the reader
                        through `title`. */}
                    <span
                      data-group-title
                      title={`name : ${name}`}
                      class="flex min-w-0 items-center gap-1.5"
                    >
                      <span data-group-text class="min-w-0 truncate">
                        <span class="text-control-xs font-semibold text-primary">name</span>
                        <span class="text-muted-foreground">:</span>
                        <span class="font-mono text-control-xs">{name}</span>
                      </span>
                      {/* Orange when the last Confirm found something: the warning renders inside
                          the body, which announces nothing while the group is folded. */}
                      <span
                        data-state={groupState(name)}
                        aria-label={groupState(name)}
                        title={
                          groupState(name) === "incomplete"
                            ? "unfinished — open to see why"
                            : groupState(name)
                        }
                        class={[
                          "ml-1 h-2 w-2 shrink-0 rounded-full",
                          {
                            "bg-success": groupState(name) === "confirmed",
                            "bg-warning": groupState(name) === "incomplete",
                            "border border-muted-foreground": groupState(name) === "unconfirmed",
                          },
                        ]}
                      />
                    </span>
                    <span data-group-actions class="ml-auto flex shrink-0 items-center gap-2">
                      {/*
                        Asks the probe rather than judging locally: an empty group passes schema
                        validation (measured — `weather = []` constructs), so completeness here was
                        never the validator's to answer, and used to be `checkGroup`'s own guess at
                        it. Since the 2026-09-16 fixes the server reports an empty group itself
                        (`empty_group_issues`, surfaced as `/groups/<name>`), Confirm now asks
                        the same question the continuous probe asks and shows its answer — one
                        source of truth instead of two that could disagree.
                      */}
                      <Button
                        title="mark this group deliberately finished"
                        onClick={summaryAction(() => {
                          // Captured now, synchronously, before any `await` — not read back off
                          // `state` once the probe answers. Mirrors `confirmNode` in
                          // processing.tsx, which reads `state.nodes[index]` the same way: an edit
                          // made while the request is in flight must confirm nothing, rather than
                          // silently getting stamped as the thing that was probed.
                          const items = state.groups[name];
                          const document = JSON.parse(JSON.stringify(state)) as CardsStore;
                          void (async () => {
                            // The server's answer, not ours: an empty group is reported by the
                            // probe since the 2026-09-16 fixes (`empty_group_issues`), so the
                            // one rule that used to live here (`checkGroup`) is gone.
                            const answer = await askProbe(document);
                            // `null` means the probe could not be asked at all (item 1: a missing
                            // dev-server proxy route, or the server being down) — not that it came
                            // back clean. Reading it as "no issues" is what let an empty group
                            // through Confirm with a green dot (final review, 2026-09-16).
                            if (answer === null) {
                              setUnfinished({
                                ...unfinished(),
                                [name]: [{
                                  message: "Could not reach DashiBoard to check this group — is the server running?",
                                }],
                              });
                              return;
                            }
                            const found = issuesForGroup(answer.issues, name).map((issue) => ({
                              message: issue.message, pointer: issue.pointer,
                            }));
                            setUnfinished({ ...unfinished(), [name]: found });
                            if (found.length === 0) confirmDefinition(`group:${name}`, items);
                          })();
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
                    would simply select nothing, which the schema has no way to say. Filtered
                    against the live list just below — the same finding does not render twice. */}
                <For each={staleFindings(name)}>
                  {(finding: Incompleteness) => (
                    <p class="rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground">
                      {finding.message}
                    </p>
                  )}
                </For>
                {/* The continuous probe's own finding for this group, live — not only what the
                    last Confirm captured. A run that failed on this group (Task 5's
                    `reportRunIssues`) lands here too, without a second Confirm. */}
                <For each={issuesForGroup(probe.issues, name)}>
                  {(issue) => (
                    <p class="rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground">
                      {issue.message}
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
