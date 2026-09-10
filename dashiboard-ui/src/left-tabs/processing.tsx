import { createEffect, createSignal, For, Show, Store } from "solid-js";

import { Button } from "../components/Button";
import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { IRField } from "../components/IRField";
import { postRequest } from "../requests";
import {
  CARDS_STORE,
  CardsStore,
  Card,
  LOADER_STORE,
  addNode,
  removeNode,
  setCard,
  exportCards,
  importCards,
  emptyCards,
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
        nodes: state.nodes.map((node, i) => String(node.id ?? i)),
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

  // Refetch when the loaded columns change, not only on mount: `$defs/col` carries the source
  // enum, so a picker rendered before a source is connected has nothing to offer.
  createEffect(
    () => metadata.map((entry) => entry.name).join("\u0000"),
    () => void loadIR(),
  );

  const cardTypes = () => Object.keys(payload()?.cards ?? {}).sort();

  return (
    <div>
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
          <Button
            onClick={() => {
              addNode({ type: chosen() } as Card);
              void loadIR(); // the new node becomes referenceable
            }}
          >
            Add card
          </Button>
        </div>
      </Show>

      <For each={state.nodes}>
        {(node, index) => (
          <div class="my-4 rounded border border-gray-200 p-4">
            <div class="mb-2 flex items-center justify-between">
              <span class="font-semibold text-blue-900">{String(node.card.type)}</span>
              <Button
                danger
                onClick={() => {
                  removeNode(index());
                  void loadIR();
                }}
              >
                Remove
              </Button>
            </div>
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
        onChange={(value: CardsStore) => {
          importCards(value);
          void loadIR();
        }}
      >
        Upload cards
      </UploadJSONButton>
    </div>
  );
}
