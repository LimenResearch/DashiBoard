import { createEffect, createMemo, createSignal, For, Show, Store, reconcile } from "solid-js";

import { Button } from "../components/Button";
import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { IRField } from "../components/IRField";
import { GroupsEditor } from "../components/GroupsEditor";
import { Disclosure, summaryAction } from "../components/Disclosure";
import { postRequest } from "../requests";
import {
  CARDS_STORE,
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
import { checkFields, checkNode, type Incompleteness } from "../completeness";

/** The card half of the document, as `evaluate-pipeline` takes it. */
export function getCards(state: Store<CardsStore>) {
  return { nodes: state.nodes, groups: state.groups };
}

type Payload = { defs: Defs; cards: { [type: string]: IRNode } };

export function Cards() {
  const [state] = CARDS_STORE;
  const [metadata] = LOADER_STORE;
  const [probe, setProbe] = PROBE_STORE;

  const [payload, setPayload] = createSignal<Payload | null>(null);
  const [chosen, setChosen] = createSignal("");
  const [error, setError] = createSignal<string | null>(null);

  // The IR is fetched from `get-card-ir`, not `get-card-widgets`: the widget path is the
  // hand-written second description A2 deletes, and the IR is what the renderer builds from
  // (§13). Which nodes and groups are referenceable depends on the document being edited, not
  // only on the source, so this re-runs when either changes.
  async function loadIR() {
    const received = (await postRequest(
      "get-card-ir",
      {
        cols: metadata.map((entry) => entry.name),
        // Only names that exist. `Pipelines.get_id` is the naming rule, and it has no index
        // fallback — a node with no `id` is called "" and is referenceable by nobody, so
        // offering its position as a name offered one the server would never resolve.
        nodes: state.nodes.map((node) => node.id).filter((id): id is string => !!id),
        groups: Object.keys(state.groups),
      },
      null,
    )) as Payload | null;
    if (!received) {
      setError("Could not reach DashiBoard. Is the server running?");
      return;
    }
    setError(null);
    setPayload(received);
    const types = Object.keys(received.cards).sort();
    if (!chosen() && types.length > 0) setChosen(types[0]);
  }

  // Refetch whenever the *vocabulary* changes — columns, node ids, group names — not only on
  // mount. `$defs/col` carries the source enum, so a picker rendered before a source is connected
  // has nothing to offer; and adding or renaming a card changes what `nodes:` and `through:` can
  // name. Driving this from the document rather than from explicit calls after each mutation also
  // sidesteps reading the store before Solid has settled the write.
  createEffect(
    () =>
      [
        metadata.map((entry) => entry.name).join("\u0000"),
        state.nodes.map((node) => node.id ?? "").join("\u0000"),
        Object.keys(state.groups).join("\u0000"),
      ].join("\u0001"),
    () => void loadIR(),
  );

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

  // Probe on every document change. Construction is cheap and materialises nothing, so this is
  // the feedback loop for references the schema cannot check.
  /**
   * Ask the probe about a document and return something of the right shape.
   *
   * Shared by the continuous run and by Confirm. Confirm asks *again* rather than reading the
   * last answer, because the continuous probe is asynchronous: press Confirm on a card added a
   * moment ago and the reply is still in flight, so the stale answer says nothing is wrong and
   * the card confirms green. One request per press is the cost of the answer being current.
   */
  async function askProbe(document: CardsStore): Promise<ProbeStore> {
    const result = await postRequest("probe-pipeline", document, null);
    const reported = result as ProbeStore | null;
    const usable =
      reported !== null &&
      typeof reported === "object" &&
      Array.isArray(reported.nodes) &&
      Array.isArray(reported.errors);
    return usable
      ? { ...reported, issues: Array.isArray(reported.issues) ? reported.issues : [] }
      : emptyProbe();
  }

  async function runProbe(document: CardsStore | null) {
    if (document === null) {
      setProbe(reconcile(emptyProbe()));
      return;
    }
    const result = await postRequest("probe-pipeline", document, null);
    // Validate the shape rather than trusting it. An unexpected response used to reach the store
    // and throw on the first `.length`, which halts Solid's reactive system for the whole page —
    // a far worse outcome than showing no probe result.
    const reported = result as ProbeStore | null;
    const usable =
      reported !== null &&
      typeof reported === "object" &&
      Array.isArray(reported.nodes) &&
      Array.isArray(reported.errors);
    // `issues` is normalised rather than required. A server predating A7 does not send it, and
    // rejecting the whole response over an absent field would silently switch the probe off
    // against it — the same class of silent failure the shape check exists to prevent.
    setProbe(
      reconcile(
        usable
          ? { ...reported, issues: Array.isArray(reported.issues) ? reported.issues : [] }
          : emptyProbe(),
      ),
    );
  }

  // Every reactive read happens in the *compute* function; the callback only performs the call.
  // Reading the store inside the callback is untracked and never updates — Solid 2 says so with
  // STRICT_READ_UNTRACKED, and its versioned skill prescribes exactly this shape. The effect must
  // also return void rather than a promise, hence the wrapper.
  createEffect(
    // Reads the store proxy, so this *tracks*. `exportCards()` would not: it goes through
    // `snapshot`, which is deliberately untracked, so using it here registered no dependency and
    // the probe never fired.
    () => JSON.stringify(state),
    (serialised) => {
      const document = JSON.parse(serialised) as CardsStore;
      void runProbe(document.nodes.length === 0 ? null : document);
    },
  );

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
  const serverFindings = (answer: ProbeStore, index: number): Incompleteness[] => {
    const schema = issuesForNode(answer.issues, index)
      .filter((issue) => issue.reason !== "unproduced")
      .map((issue) => {
      const where = fieldPath(issue.pointer);
      if (issue.missing.length > 0) {
        return { message: `Fill in ${issue.missing.join(", ")} — DashiBoard needs them to build this card.` };
      }
      if (issue.reason === "enum" && issue.allowed) {
        return {
          message: `${where || "This card"} must be one of: ${issue.allowed.map(String).join(", ")}.`,
        };
      }
      return { message: `${where || "This card"} is not accepted (${issue.reason}).` };
    });
    const absent = answer.nodes[index]?.unproduced ?? [];
    return absent.length > 0
      ? [...schema, { message: `Nothing produces ${absent.join(", ")} — check the pass-through chain.` }]
      : schema;
  };

  /**
   * Confirm in two stages, in the order that answers fastest.
   *
   * **What the card says about itself** comes first, and comes back in the same tick as the
   * press: `checkFields` walks the IR the server sent against the value the form holds, so every
   * unanswered field is named at once, each against the control that fixes it. If it finds
   * anything, that is the answer — there is nothing to ask the server about a card that is not
   * finished being written, and a round trip would only delay saying so.
   *
   * **What only the graph can answer** comes second, and only once the first stage is clean. An
   * unproduced reference, a duplicate id, a cycle: none of these is visible in one card, so none
   * of them is ours. This is also the backstop — the first stage reads the IR, which does not
   * carry every constraint the schema expresses, so a `missing` finding arriving here means the
   * walk missed something and it is surfaced rather than swallowed.
   *
   * The probe is asked again rather than read from the store, because the continuous run is
   * asynchronous: pressing Confirm on a card added a moment ago would otherwise consult an answer
   * about the document as it was before it existed.
   */
  async function confirmNode(index: number) {
    const node = state.nodes[index];
    const ir = payload()?.cards[String(node.card.type)];
    const here = [
      ...checkNode(node),
      ...(ir === undefined
        ? []
        : checkFields(ir, defsForNode(index), node.card, `/nodes/${index}/card`)),
    ];
    setUnfinished({ ...unfinished(), [index]: here });
    if (here.length > 0) return;

    const answer = await askProbe(JSON.parse(JSON.stringify(state)) as CardsStore);
    const found = serverFindings(answer, index);
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

  /** unconfirmed · incomplete · confirmed — three states, because folded, the dot is all there is. */
  const nodeState = (index: number) =>
    (unfinished()[index]?.length ?? 0) > 0
      ? "incomplete"
      : confirmedNode(index)
        ? "confirmed"
        : "unconfirmed";

  const probeNodes = createMemo(() => probe.nodes);
  const probeErrors = createMemo(() => probe.errors);
  const probeIssues = createMemo(() => probe.issues);
  // Anything the probe reported that no card claims — a group's schema failure, say. Without
  // this an issue addressed at `/groups/weather/...` would be silently dropped.
  const looseIssues = createMemo(() =>
    probeIssues().filter((issue) => !issue.pointer.startsWith("/nodes/")),
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
      <Show when={payload()} keyed>
        {(loaded: Payload) => <GroupsEditor defs={loaded.defs} />}
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
        {(node, index) => (
          <div class="my-2 rounded-sm border border-border p-2">
            <Disclosure
              bodyClass="mt-2 flex flex-col gap-1 border-t border-border pt-2"
              summary={
                <>
                  {/* Folded, this line is all that survives — so it says what the card is and
                      which name the rest of the document refers to it by. */}
                  <span class="font-mono text-control-xs font-semibold text-primary">
                    {String(node.card.type)}
                  </span>
                  <span class="text-muted-foreground">:</span>
                  <span class="font-mono text-control-xs">
                    {node.id || <span class="text-destructive italic">unnamed</span>}
                  </span>
                  {/*
                    Orange when the last Confirm found something. Folded, this dot is the only
                    thing on screen, so a warning that renders inside the body announces itself
                    nowhere — which is the state this third colour exists for.
                  */}
                  <span
                    data-state={nodeState(index())}
                    aria-label={nodeState(index()).replace("-", " ")}
                    title={
                      nodeState(index()) === "incomplete"
                        ? "unfinished — open to see why"
                        : nodeState(index())
                    }
                    class={[
                      "ml-1 h-2 w-2 shrink-0 rounded-full",
                      {
                        "bg-success": nodeState(index()) === "confirmed",
                        "bg-warning": nodeState(index()) === "incomplete",
                        "border border-muted-foreground": nodeState(index()) === "unconfirmed",
                      },
                    ]}
                  />
                  <span class="ml-auto flex items-center gap-2">
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
                <p class="mb-2 rounded-sm border border-destructive/30 bg-destructive/10 p-2 text-control-xs text-destructive">
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
              keyed
            >
              {(cardIR: IRNode) => (
                <IRField
                  node={cardIR}
                  defs={defsForNode(index())}
                  label={String(node.card.type)}
                  value={node.card}
                  onChange={(card) => setCard(index(), card as Card)}
                />
              )}
            </Show>
            </Disclosure>
          </div>
        )}
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
