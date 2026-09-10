import { createEffect, createMemo, createSignal, For, Show, Store, reconcile } from "solid-js";

import { Button } from "../components/Button";
import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { IRField } from "../components/IRField";
import { GroupsEditor } from "../components/GroupsEditor";
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
import type { Defs, IRNode } from "../ir";

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
        <div class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          <For each={looseIssues()}>
            {(issue) => (
              <p>
                <span class="font-mono text-xs">{issue.pointer}</span> — {issue.message}
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
        <p class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-red-800">{error()}</p>
      </Show>

      <Show when={payload()} fallback={<p class="text-gray-500">Loading card descriptions…</p>}>
        <div class="flex items-center gap-3 p-4">
          <label for="card-type" class="text-sm font-semibold text-blue-800">
            Card type
          </label>
          <select
            id="card-type"
            class="rounded border border-gray-200 py-0.5 pl-2"
            value={chosen()}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            <For each={cardTypes()}>{(type) => <option value={type}>{type}</option>}</For>
          </select>
          <Button onClick={() => addNode({ type: chosen() } as Card)}>Add card</Button>
        </div>
      </Show>

      {/*
        Groups come before the cards that refer to them: a card's `groups:` selector can only
        offer names that already exist, so authoring in the other order means scrolling past the
        cards to define a group and back up to use it.
      */}
      <Show when={payload()} keyed>
        {(loaded: Payload) => <GroupsEditor defs={loaded.defs} />}
      </Show>

      <For each={state.nodes}>
        {(node, index) => (
          <div class="my-4 rounded border border-gray-200 p-4">
            <div class="mb-2 flex items-center justify-between gap-3">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-blue-900">{String(node.card.type)}</span>
                {/*
                  The node's name, not the card's. It is what another card's `nodes:` selector or
                  `through:` chain refers to, and `Pipelines.get_id` defaults a missing one to "",
                  so two unnamed cards collide and the whole document is rejected.
                */}
                <input
                  class="rounded border border-gray-200 px-2 py-0.5 font-mono text-xs"
                  aria-label="node id"
                  value={node.id ?? ""}
                  onChange={(event) => setNodeId(index(), event.currentTarget.value)}
                />
              </div>
              <Button danger onClick={() => removeNode(index())}>
                Remove
              </Button>
            </div>
            {/*
              A7: the probe addresses each failure by JSON Pointer, so it is shown on the card it
              belongs to, naming the field and — for an enum — what would have been accepted.
              Attaching to the whole page was the behaviour this replaces.
            */}
            <For each={schemaIssuesForNode(index())}>
              {(issue: ProbeIssue) => (
                <p class="mb-2 rounded border border-red-200 bg-red-50 p-2 text-xs text-red-800">
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
                <div class="mb-2 text-xs">
                  <Show when={reported.unproduced.length > 0}>
                    <p class="rounded border border-red-200 bg-red-50 p-2 text-red-800">
                      nothing produces {reported.unproduced.join(", ")} — check the pass-through
                      chain, which names a column rather than routing through one
                    </p>
                  </Show>
                  <p class="text-gray-600">
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
              fallback={<p class="text-gray-500">No description for this card type.</p>}
              keyed
            >
              {(cardIR: IRNode) => (
                <IRField
                  node={cardIR}
                  defs={payload()!.defs}
                  label={String(node.card.type)}
                  value={node.card}
                  onChange={(card) => setCard(index(), card as Card)}
                />
              )}
            </Show>
          </div>
        )}
      </For>

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
  );
}
