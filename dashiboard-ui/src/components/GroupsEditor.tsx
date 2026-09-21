import { createMemo, createSignal, For, Show } from "solid-js";

import { Button } from "./Button";
import { Disclosure, summaryAction } from "./Disclosure";
import { SummaryTitle } from "./SummaryTitle";
import { SelectorField } from "./SelectorField";
import type { SelectorItem } from "../selector";
import {
  CARDS_STORE,
  PROBE_STORE,
  addGroup,
  exportCards,
  issuesForGroup,
  recordVerdict,
  verdictOf,
  askedOf,
  stillAsked,
  documentFindings,
  rejectDocument,
  forgetVerdict,
  removeGroup,
  renameGroup,
  setGroup,
  type Selector,
} from "../stores";
import { askProbe } from "../probe";
import { issueFindings } from "../findings";
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
  // The last verdict on exactly this group's content — null once it is edited (`stores.ts`,
  // verdicts). Findings travel with it, so there is no per-component list to keep in step.
  const verdict = (name: string) => verdictOf(`group:${name}`, state.groups[name]);
  /** unconfirmed · confirmed · rejected — amber until asked; folded, the dot is all there is. */
  const groupState = (name: string) => verdict(name)?.verdict ?? "unconfirmed";
  const findings = (name: string): Incompleteness[] => {
    const v = verdict(name);
    return v?.verdict === "rejected" ? v.findings : [];
  };
  // What the continuous probe says live about a group is only its *warnings*. Its errors are not
  // shown here: red is reserved for what Confirm or a Run found (decided 2026-09-17).
  const warnings = createMemo(() => probe.issues.filter((issue) => issue.severity === "warning"));

  // The `$defs/variable` node: one item of a selector list, which is exactly what a group holds.
  const itemNode = () => (props.defs.variable ?? {}) as IRNode;

  return (
    <div>
      <div class="flex items-center gap-2 p-3">
        <span class="text-control-xs font-semibold text-primary">Groups</span>
        <Button onClick={() => void addGroup()}>Add group</Button>
      </div>

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
          {(name) => {
            // Why the last name typed into this group was refused — per group, since the `<For>`
            // callback is a per-row owner, and read inside the group that caused it. It used to be
            // one banner above the whole list, which scrolls away from the group being renamed
            // and does not say which group it is about (owner, 2026-09-17). A card's refusal is
            // the same move (`processing.tsx`, `rename`).
            const [nameError, setNameError] = createSignal<string | null>(null);
            function rename(field: HTMLInputElement) {
              const to = field.value.trim();
              if (renameGroup(name, to)) {
                setNameError(null);
                return;
              }
              // The document refused, so the screen must not keep showing the name that was typed.
              field.value = name;
              setNameError(
                to === "" ? "A group needs a name." : `There is already a group called "${to}".`,
              );
            }

            return (
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
                    <SummaryTitle hook="group" kind="Group" name={name} state={groupState(name)} />
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
                          // One plain snapshot, taken before any `await`, is what gets probed
                          // and what the verdict binds to — never a store proxy, which would
                          // read the group as it is once the reply lands. Mirrors `confirmNode`
                          // in processing.tsx: an edit made while the request is in flight must
                          // leave the group unasked, not stamp it with an answer about content
                          // the server never saw.
                          const document = exportCards();
                          const items = document.groups[name];
                          const key = `group:${name}`;
                          // The answer is only worth recording while this group is still the
                          // one that was asked: removed and re-added under the same name, it is
                          // a new group that nobody asked about (`stores.ts`, `askedOf`).
                          const asked = askedOf(key);
                          const decide = (found: Incompleteness[]) =>
                            recordVerdict(key, items, found.length > 0 ? "rejected" : "confirmed", found);
                          void (async () => {
                            // The server's answer, not ours: an empty group is reported by the
                            // probe since the 2026-09-16 fixes (`empty_group_issues`), so the
                            // one rule that used to live here (`checkGroup`) is gone.
                            const answer = await askProbe(document);
                            if (!stillAsked(key, asked)) return;
                            // `null` means the probe could not be asked at all (item 1: a missing
                            // dev-server proxy route, or the server being down) — not that it came
                            // back clean. Reading it as "no issues" is what let an empty group
                            // through Confirm with a green dot (final review, 2026-09-16).
                            if (answer === null) {
                              decide([{
                                message: "Could not reach DashiBoard to check this group — is the server running?",
                              }]);
                              return;
                            }
                            // A document that does not build is nobody's item (a loop): it
                            // goes on the document's own verdict, said once next to Run, and the
                            // group is left unasked — same rule as `confirmNode`.
                            const loose = documentFindings(answer);
                            if (loose.length > 0) {
                              forgetVerdict(key);
                              rejectDocument(document, loose);
                              return;
                            }
                            // A warning is not a finding: it renders live, amber, and never
                            // stops Confirm.
                            decide(issueFindings(
                              issuesForGroup(answer.issues, name).filter((issue) => issue.severity !== "warning"),
                            ));
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
                {/* What Confirm (or a failed run, through `rejectFromIssues`) found on this exact
                    content: red, and only while the verdict is a rejection — an edit drops it
                    with the verdict. */}
                <For each={findings(name)}>
                  {(finding: Incompleteness) => (
                    <p
                      data-finding
                      class="rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-control-xs text-destructive"
                    >
                      {finding.message}
                    </p>
                  )}
                </For>
                {/* A refused name, with the other banners rather than under the field: seen in a
                    browser with the field between two red banners, it read as two kinds of thing
                    (owner, 2026-09-17). One stack, then the fields. */}
                <Show when={nameError()}>
                  <p
                    data-name-error
                    class="rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-control-xs text-destructive"
                  >
                    {nameError()}
                  </p>
                </Show>
                {/* Live, amber, and not a verdict: the document is legal and would run. */}
                <For each={issuesForGroup(warnings(), name)}>
                  {(issue) => (
                    <p
                      data-issue-severity="warning"
                      class="rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground"
                    >
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
                    onChange={(event) => rename(event.currentTarget)}
                  />
                </div>
                <SelectorField
                  itemNode={itemNode()}
                  // A group naming itself is a loop — measured, and rejected as one — so its
                  // own name is not on offer inside it.
                  defs={withoutOption(props.defs, "group", name)}
                  label="columns"
                  value={state.groups[name]}
                  onChange={(items: SelectorItem[]) => setGroup(name, items as Selector[])}
                />
              </Disclosure>
            </div>
            );
          }}
        </For>
      </Show>
    </div>
  );
}
