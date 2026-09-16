import {
  createEffect, createMemo, createSignal, For, onCleanup, Show, Store, reconcile, untrack,
} from "solid-js";

import { Button } from "../components/Button";
import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { IRField } from "../components/IRField";
import { GroupsEditor } from "../components/GroupsEditor";
import { Disclosure, summaryAction } from "../components/Disclosure";
import { postRequest } from "../requests";
import {
  CARDS_STORE,
  CARDS_JSON,
  CardsStore,
  Card,
  LOADER_STORE,
  addNode,
  removeNode,
  setCard,
  setNodeId,
  isConfirmed,
  confirmDefinition,
  issuesForNode,
  fieldPath,
  exportCards,
  importCards,
  emptyCards,
  emptyProbe,
  PROBE_STORE,
  type ProbeNode,
  type ProbeStore,
  type ProbeIssue,
} from "../stores";
import { defaultsFor, withoutOption, type Defs, type IRNode } from "../ir";
import { checkNode, type Incompleteness } from "../completeness";
import { askProbe } from "../probe";

/** The card half of the document, as `evaluate-pipeline` takes it. */
export function getCards(state: Store<CardsStore>) {
  return { nodes: state.nodes, groups: state.groups };
}

type Payload = { defs: Defs; cards: { [type: string]: IRNode } };

/** Everything a card may name: the source's columns, the other cards, the groups. */
type Vocabulary = { cols: string[]; nodes: string[]; groups: string[] };

/**
 * One IR fetch per vocabulary *change*, which reference equality cannot deliver.
 *
 * The three lists are rebuilt from the stores on every write, so a fresh object arrives whenever
 * anything in the document moves — a field edited, a chip picked. Comparing their contents is
 * what keeps the refetch tied to the vocabulary rather than to the keystroke.
 */
const sameVocabulary = (a: Vocabulary, b: Vocabulary) =>
  (["cols", "nodes", "groups"] as const).every(
    (part) => a[part].length === b[part].length && a[part].every((v, at) => v === b[part][at]),
  );

export function Cards() {
  const [state] = CARDS_STORE;
  const [metadata] = LOADER_STORE;
  const [probe, setProbe] = PROBE_STORE;

  const [payload, setPayload] = createSignal<Payload | null>(null);
  const [chosen, setChosen] = createSignal("");
  const [error, setError] = createSignal<string | null>(null);

  // `cards` is fetched once and kept; only `defs` follows the vocabulary. See the handler.
  const [cardIRs, setCardIRs] = createSignal<{ [type: string]: IRNode } | null>(null);

  // The IR is what the renderer builds from, and since A2 it is the only description of a card
  // that exists (§13). Which nodes and groups are referenceable depends on the document being
  // edited, not only on the source, so this re-runs when either changes.
  //
  // The vocabulary arrives as an argument rather than being read here: this runs from an effect
  // *callback*, where a read of a store or a signal is untracked — so reading the document here
  // would be a dependency the effect does not have, and the diagnostics say so.
  async function loadIR(vocabulary: Vocabulary) {
    // Captured before the request, not re-read from the signal after `setCardIRs` below: a
    // signal write stages into `_pendingValue` and an untracked read from this plain async
    // continuation is not guaranteed to observe it before the next flush (Solid 2's transition
    // model, unlike Solid 1's immediate same-tick reads). `untrack` says that is deliberate:
    // this is a cache lookup, not something the fetch should re-run for.
    const previousCards = untrack(cardIRs);
    const include = previousCards === null ? ["defs", "cards"] : ["defs"];
    const received = (await postRequest(
      "get-card-ir",
      { ...vocabulary, include },
      null,
    )) as Partial<Payload> | null;
    if (!received || !received.defs) {
      setError("Could not reach DashiBoard. Is the server running?");
      return;
    }
    setError(null);
    const cards = received.cards ?? previousCards;
    if (cards === null) return;                       // cannot happen on the first call
    setCardIRs(cards);
    setPayload({ defs: received.defs, cards });
    const types = Object.keys(cards).sort();
    if (!chosen() && types.length > 0) setChosen(types[0]);
  }

  // Refetch whenever the *vocabulary* changes — columns, node ids, group names — not only on
  // mount. `$defs/col` carries the source enum, so a picker rendered before a source is connected
  // has nothing to offer; and adding or renaming a card changes what `nodes:` and `through:` can
  // name. Driving this from the document rather than from explicit calls after each mutation also
  // sidesteps reading the store before Solid has settled the write.
  //
  // The memo is where the stores are read, so those reads are the effect's dependencies, and the
  // value it produces is what the request is built from — it cannot drift from what triggered it.
  const vocabulary = createMemo<Vocabulary>(
    () => ({
      cols: metadata.map((entry) => entry.name),
      // Only names that exist. `Pipelines.get_id` is the naming rule, and it has no index
      // fallback — a node with no `id` is called "" and is referenceable by nobody, so
      // offering its position as a name offered one the server would never resolve.
      nodes: state.nodes.map((node) => node.id).filter((id): id is string => !!id),
      groups: Object.keys(state.groups),
    }),
    { equals: sameVocabulary },
  );
  createEffect(vocabulary, (current) => void loadIR(current));

  const cardTypes = () => Object.keys(payload()?.cards ?? {}).sort();

  /**
   * The vocabulary this card may draw on: everything, minus its own name.
   *
   * A card naming itself — as an input, or as a step in a `through` chain — is a cycle, and the
   * server rejects the whole document for it. Offering it is offering a choice that cannot come
   * out well, so it is removed from the vocabulary rather than validated after the fact.
   */
  const defsForNode = (index: number): Defs => {
    const defs = payload()!.defs;
    const self = state.nodes[index]?.id;
    return self ? withoutOption(defs, "node", self) : defs;
  };

  // The continuous probe. Three things it does that a plain effect did not:
  //
  //   * reads the document from `CARDS_JSON`, which persistence already serialises — one deep
  //     read of the store instead of two;
  //   * waits 200 ms of quiet before asking, so a burst of edits is one request;
  //   * numbers each request and applies a reply only if it is still the newest, because
  //     replies are async and a slow answer to an old document used to overwrite a fast answer
  //     to the new one.
  let probeSeq = 0;
  let probeTimer: ReturnType<typeof setTimeout> | undefined;
  const PROBE_QUIET_MS = 200;

  createEffect(CARDS_JSON, (json) => {
    clearTimeout(probeTimer);
    probeTimer = setTimeout(() => {
      const document = JSON.parse(json) as CardsStore;
      if (document.nodes.length === 0) {
        probeSeq += 1;
        setProbe(reconcile(emptyProbe()));
        return;
      }
      const seq = ++probeSeq;
      void askProbe(document).then((answer) => {
        if (seq !== probeSeq) return;            // a newer request is out; this answer is stale
        setProbe(reconcile(answer));
      });
    }, PROBE_QUIET_MS);
  });

  // A pending probe must not outlive the tab: the timer would post after unmount, and a reply
  // already in flight would write the store. Moving the sequence past any live request discards it.
  onCleanup(() => {
    clearTimeout(probeTimer);
    probeSeq = Number.MAX_SAFE_INTEGER;
  });

  // Memos are a tracking scope; reading `probe.nodes` straight from JSX is not enough here.
  // What Confirm found the last time it was pressed, per card. Not run continuously: the point
  // of the step is that the author says when they are done, and a panel that argues while you
  // type is the thing it exists to replace.
  const [unfinished, setUnfinished] = createSignal<Record<number, Incompleteness[]>>({});
  const confirmedNode = (index: number) => isConfirmed(`node:${index}`, state.nodes[index]);

  /**
   * What the server says about this card, as something a person can act on.
   *
   * Confirm has to ask it. The UI's own rules only cover what DashiBoard *accepts* — by design —
   * so on their own they let an empty card through: `checkNode` sees a name and is satisfied,
   * while construction fails on `method` and `inputs`. The probe already knows; Confirm was
   * simply not reading it.
   */
  /**
   * Schema issues as findings, one per control rather than one per issue.
   *
   * A `required` failure names every absent field at once and carries a `related` pointer per
   * name (A7), so the server already knows which control each belongs to — the work here is
   * placing them, not finding them.
   */
  const issueFindings = (issues: readonly ProbeIssue[]): Incompleteness[] =>
    issues.flatMap((issue) => {
      if (issue.severity === "warning") {
        return [{ message: issue.message, pointer: issue.pointer, severity: "warning" as const }];
      }
      if (issue.missing.length > 0) {
        return issue.missing.map((name, at) => ({
          message: "needs a value",
          pointer: issue.related[at] ?? `${issue.pointer}/${name}`,
        }));
      }
      if (issue.reason === "enum" && issue.allowed) {
        return [{
          message: `must be one of: ${issue.allowed.map(String).join(", ")}`,
          pointer: issue.pointer,
        }];
      }
      return [{ message: `not accepted (${issue.reason})`, pointer: issue.pointer }];
    });

  /**
   * Ask Pipelines about this card, and only this card.
   *
   * `POST /validate-card` builds the card's own schema from the same vocabularies the IR was
   * built from and validates against it — the server's own check, not a copy of it. There was a
   * walk here that re-implemented `required` and `minItems` in TypeScript; measured against
   * `validate_pipeline_schema` it found exactly the same set, so it is gone.
   */
  async function askCard(index: number): Promise<ProbeIssue[]> {
    const answer = (await postRequest(
      "validate-card",
      {
        card: JSON.parse(JSON.stringify(state.nodes[index].card)),
        cols: metadata.map((entry) => entry.name),
        nodes: state.nodes.map((node) => node.id).filter((id): id is string => !!id),
        groups: Object.keys(state.groups),
        base: `/nodes/${index}/card`,
      },
      null,
    )) as { issues?: ProbeIssue[]; errors?: string[] } | null;
    if (answer === null) return [];
    return Array.isArray(answer.issues) ? answer.issues : [];
  }

  /**
   * What only the whole document can answer: a reference nothing produces, and — as a backstop —
   * any schema failure `validate-card` could not see because it needs the other cards.
   */
  const graphFindings = (answer: ProbeStore, index: number): Incompleteness[] => {
    // A warning never counts as unfinished — it still renders live through the probe path, in
    // the warning style, but does not stop Confirm from marking the card done.
    const schema = issueFindings(
      issuesForNode(answer.issues, index).filter(
        (issue) => issue.reason !== "unproduced" && issue.severity !== "warning",
      ),
    );
    const absent = answer.nodes[index]?.unproduced ?? [];
    return absent.length > 0
      ? [...schema, { message: `Nothing produces ${absent.join(", ")} — check the pass-through chain.` }]
      : schema;
  };

  async function confirmNode(index: number) {
    const node = state.nodes[index];

    // Ours alone: an unnamed node is a document the server accepts, so if this does not say it
    // nobody will. It is also the cheapest question, and answering it first keeps a card with no
    // name from spending two round trips to be told so.
    const named = checkNode(node);
    if (named.length > 0) {
      setUnfinished({ ...unfinished(), [index]: named });
      return;
    }

    const issues = await askCard(index);
    if (issues.length > 0) {
      setUnfinished({ ...unfinished(), [index]: issueFindings(issues) });
      return;
    }

    const answer = await askProbe(JSON.parse(JSON.stringify(state)) as CardsStore);
    const found = graphFindings(answer, index);
    setUnfinished({ ...unfinished(), [index]: found });
    if (found.length === 0) confirmDefinition(`node:${index}`, node);
  }

  /**
   * Findings follow their card when an earlier one is removed.
   *
   * Both this map and the confirmations are keyed by *position*, so a splice slides every later
   * card's answer onto its neighbour. Confirmations survive that on their own — they store a
   * signature of the content, so a shifted one simply stops matching — but findings carry no
   * such check, and a precise field pointer attached to the wrong card is worse than no pointer
   * at all. A stable per-node key would retire both workarounds; there is nothing in the document
   * to make one from yet.
   */
  function shiftPast<T>(record: Record<number, T>, removed: number): Record<number, T> {
    const out: Record<number, T> = {};
    for (const [key, value] of Object.entries(record)) {
      const at = Number(key);
      if (at < removed) out[at] = value;
      else if (at > removed) out[at - 1] = value;
    }
    return out;
  }

  const probeNodes = createMemo(() => probe.nodes);
  const probeErrors = createMemo(() => probe.errors);
  const probeIssues = createMemo(() => probe.issues);
  // Anything the probe reported that no other view claims. `/nodes/...` renders on its card, and
  // since Task 6 `/groups/...` renders on its group (the groups editor's live `<For>` over
  // `issuesForGroup`) — so both are excluded here, or an empty-group finding would show twice.
  const looseIssues = createMemo(() =>
    probeIssues().filter(
      (issue) => !issue.pointer.startsWith("/nodes/") && !issue.pointer.startsWith("/groups/"),
    ),
  );
  // Schema failures only. The probe also reports unproduced references here, for clients that
  // want one uniform list, but this one renders those from `nodes[].unproduced` just below —
  // with guidance about the pass-through chain that the server's terse message cannot carry.
  const schemaIssuesForNode = (index: number) =>
    issuesForNode(probeIssues(), index).filter((issue) => issue.reason !== "unproduced");

  return (
    <div>
      <Show when={probeErrors().length > 0 || looseIssues().length > 0}>
        <div class="mb-4 rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-control-xs text-destructive">
          <For each={looseIssues()}>
            {(issue) => (
              <p>
                <span class="font-mono text-control-xs">{issue.pointer}</span> — {issue.message}
              </p>
            )}
          </For>
          {/* A failure with no pointer — a cyclic graph, a duplicate id — has only its message. */}
          <Show when={looseIssues().length === 0 && probeErrors().length > 0}>
            <p>{probeErrors().join("; ")}</p>
          </Show>
        </div>
      </Show>

      <Show when={error()}>
        <p class="mb-4 rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-destructive">{error()}</p>
      </Show>

      {/*
        Groups first, as their own section: a card's `groups:` selector can only offer names that
        already exist, so authoring in the other order means scrolling past the cards to define a
        group and back up to use it. "Add card" then sits directly above the cards it creates,
        rather than above the groups — a control belongs next to what it produces.
      */}
      <Show when={payload()}>
        <GroupsEditor defs={payload()!.defs} />
      </Show>

      <Show when={payload()} fallback={<p class="text-muted-foreground">Loading card descriptions…</p>}>
        <div class="flex items-center gap-2 p-3">
          <label for="card-type" class="text-control-xs font-semibold text-primary">
            Card type
          </label>
          <select
            id="card-type"
            class="h-control-xs rounded-sm border border-border pl-2 text-control-xs"
            value={chosen()}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            <For each={cardTypes()}>{(type) => <option value={type}>{type}</option>}</For>
          </select>
          {/*
            The card starts with the defaults its IR declares, rather than with only a type. The
            form displayed them either way; the document did not carry them, so what was on screen
            and what a download produced disagreed.
          */}
          <Button
            onClick={() => {
              const ir = payload()?.cards[chosen()];
              const defaults = ir === undefined ? undefined : defaultsFor(ir, payload()!.defs);
              addNode({ type: chosen(), ...(defaults as object) } as Card);
            }}
          >
            Add card
          </Button>
        </div>
      </Show>

      <For each={state.nodes}>
        {(node, index) => {
          /** unconfirmed · incomplete · confirmed — three states, because folded, the dot is all there is. */
          const nodeState = createMemo(() =>
            (unfinished()[index()]?.length ?? 0) > 0
              ? "incomplete"
              : confirmedNode(index())
                ? "confirmed"
                : "unconfirmed",
          );

          return (
          <div class="my-2 rounded-sm border border-border p-2">
            <Disclosure
              bodyClass="mt-2 flex flex-col gap-1 border-t border-border pt-2"
              summary={
                <>
                  {/* Folded, this line is all that survives — so it says what the card is and
                      which name the rest of the document refers to it by. A long type name (e.g.
                      `dimensionality_reduction`) used to push Confirm/Remove past the pane's edge.
                      `text-overflow: ellipsis` only renders in a block/inline formatting context —
                      on a flex box `overflow:hidden` just hard-clips a child mid-character — so
                      `truncate` lives on the inner, non-flex `data-card-text` span around the text
                      run, not on this flex wrapper. The full text still reaches the reader through
                      `title`. */}
                  <span
                    data-card-title
                    title={`${String(node.card.type)} : ${node.id || "unnamed"}`}
                    class="flex min-w-0 items-center gap-1.5"
                  >
                    <span data-card-text class="min-w-0 truncate">
                      <span class="font-mono text-control-xs font-semibold text-primary">
                        {String(node.card.type)}
                      </span>
                      <span class="text-muted-foreground">:</span>
                      <span class="font-mono text-control-xs">
                        {node.id || <span class="text-destructive italic">unnamed</span>}
                      </span>
                    </span>
                    {/*
                      Orange when the last Confirm found something. Folded, this dot is the only
                      thing on screen, so a warning that renders inside the body announces itself
                      nowhere — which is the state this third colour exists for.
                    */}
                    <span
                      data-state={nodeState()}
                      aria-label={nodeState().replace("-", " ")}
                      title={
                        nodeState() === "incomplete"
                          ? "unfinished — open to see why"
                          : nodeState()
                      }
                      class={[
                        "ml-1 h-2 w-2 shrink-0 rounded-full",
                        {
                          "bg-success": nodeState() === "confirmed",
                          "bg-warning": nodeState() === "incomplete",
                          "border border-muted-foreground": nodeState() === "unconfirmed",
                        },
                      ]}
                    />
                  </span>
                  <span data-card-actions class="ml-auto flex shrink-0 items-center gap-2">
                    {/*
                      The distinction it carries is *completeness*, not validity, and the two come
                      apart in both directions: an empty group passes schema validation (measured —
                      `weather = []` constructs) and is still not something anyone meant to define,
                      while a blank `suffix` is filled in and the schema rejects it. So Confirm
                      cannot just be the validator — see `confirmNode` for what it is instead.
                    */}
                    <Button
                      title="mark this card deliberately finished"
                      onClick={summaryAction(() => {
                        void confirmNode(index());
                      })}
                    >
                      Confirm
                    </Button>
                    <Button
                      variant="danger"
                      onClick={summaryAction(() => {
                        const removed = index();
                        removeNode(removed);
                        setUnfinished(shiftPast(unfinished(), removed));
                      })}
                    >
                      Remove
                    </Button>
                  </span>
                </>
              }
            >
              <div class="flex items-center gap-2">
                <label
                  for={`node-id-${index()}`}
                  class="w-32 shrink-0 text-control-xs font-semibold text-primary"
                >
                  name
                </label>
                {/*
                  The node's name, not the card's. It is what another card's `nodes:` selector or
                  `through:` chain refers to, and `Pipelines.get_id` defaults a missing one to "",
                  so two unnamed cards collide and the whole document is rejected.
                */}
                <input
                  id={`node-id-${index()}`}
                  class="h-control-xs rounded-sm border border-border px-2 font-mono text-control-xs"
                  aria-label="node id"
                  value={node.id ?? ""}
                  onChange={(event) => setNodeId(index(), event.currentTarget.value)}
                />
              </div>
            {/*
              A7: the probe addresses each failure by JSON Pointer, so it is shown on the card it
              belongs to, naming the field and — for an enum — what would have been accepted.
              Attaching to the whole page was the behaviour this replaces.
            */}
            {/*
              Warning rather than destructive: the document is legal and would run. What it would
              not do is anything useful, which the schema has no way to say.
            */}
            <For each={unfinished()[index()] ?? []}>
              {(finding: Incompleteness) => (
                <p
                  data-finding
                  class="mb-2 rounded-sm border border-warning/40 bg-warning/10 p-2 text-control-xs text-foreground"
                >
                  {/* Same shape as a server finding just below: the field in mono, then what to
                      do. Where they came from is not the reader's problem. */}
                  <Show when={finding.pointer && fieldPath(finding.pointer) !== ""}>
                    <span class="font-mono">{fieldPath(finding.pointer!)}</span>{" — "}
                  </Show>
                  {finding.message}
                </p>
              )}
            </For>
            <For each={schemaIssuesForNode(index())}>
              {(issue: ProbeIssue) => (
                <p
                  data-issue-severity={issue.severity ?? "error"}
                  class={[
                    "mb-2 rounded-sm border p-2 text-control-xs",
                    issue.severity === "warning"
                      ? "border-warning/40 bg-warning/10 text-foreground"
                      : "border-destructive/30 bg-destructive/10 text-destructive",
                  ]}
                >
                  <Show when={fieldPath(issue.pointer) !== ""}>
                    <span class="font-mono">{fieldPath(issue.pointer)}</span>{" — "}
                  </Show>
                  <Show when={issue.reason === "enum" && issue.allowed} fallback={issue.message}>
                    <>
                      {JSON.stringify(issue.found)} is not one of{" "}
                      {(issue.allowed ?? []).map(String).join(", ")}
                    </>
                  </Show>
                  <Show when={issue.missing.length > 0}>
                    {" ("}
                    {issue.missing.join(", ")}
                    {")"}
                  </Show>
                </p>
              )}
            </For>
            <Show when={probeNodes()[index()]} keyed>
              {(reported: ProbeNode) => (
                <div class="mb-2 text-control-xs">
                  <Show when={reported.unproduced.length > 0}>
                    <p class="rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-destructive">
                      nothing produces {reported.unproduced.join(", ")} — check the pass-through
                      chain, which names a column rather than routing through one
                    </p>
                  </Show>
                  <p class="text-muted-foreground">
                    resolves to: {reported.inputs.join(", ") || "—"}
                    <Show when={reported.outputs.length > 0}>
                      {" "}→ {reported.outputs.join(", ")}
                    </Show>
                  </p>
                </div>
              )}
            </Show>
            <Show
              when={payload()?.cards[String(node.card.type)]}
              fallback={<p class="text-muted-foreground">No description for this card type.</p>}
            >
              <IRField
                node={payload()!.cards[String(node.card.type)]}
                defs={defsForNode(index())}
                label={String(node.card.type)}
                idPrefix={`node-${index()}`}
                value={node.card}
                onChange={(card) => setCard(index(), card as Card)}
              />
            </Show>
            </Disclosure>
          </div>
          );
        }}
      </For>

      <div class="flex gap-2">
        <DownloadJSONButton data={exportCards()} name="cards.json">
          Download cards
        </DownloadJSONButton>
        <UploadJSONButton
          def={emptyCards()}
          onChange={(value: CardsStore) => importCards(value)}
        >
          Upload cards
        </UploadJSONButton>
      </div>
    </div>
  );
}
