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
import { withoutOption, type Defs, type IRNode } from "../ir";

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
          <Button onClick={() => addNode({ type: chosen() } as Card)}>Add card</Button>
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
                      title="not wired yet — this will mark the definition deliberately finished"
                      onClick={summaryAction(() => {})}
                    >
                      Confirm
                    </Button>
                    <Button variant="danger" onClick={summaryAction(() => removeNode(index()))}>
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
