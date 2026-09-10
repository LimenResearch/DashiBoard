import { createSignal, For, Show, onSettled } from 'solid-js';
import { Title } from '@solidjs/meta';
import { postRequest } from '../requests';
import { IRField } from '../components/IRField';
import { FilePicker } from '../components/FilePicker';
import { Button } from '../components/Button';
import { document_store, addNode, setCard, removeNode, runRequest, type Card } from '../root';
import { Graph } from '../components/Graph';
import type { Defs, IRNode } from '../ir';

// A vertical slice, not a product. It exercises everything underneath end to end -- the runtime
// API base, the served IR, the widget mapping, the recursive renderer, and the document store --
// so the pieces can be judged by looking rather than by reading test output. No canvas, no run,
// no persistence: those are later steps in 08-frontend-rebuild.md.

type Payload = { defs: Defs; cards: { [type: string]: IRNode } };

type RunResult = {
  graph?: string;
  report?: unknown;
  summaries?: unknown;
  visualization?: (string | null)[];
};

export default function Home() {
  const [payload, setPayload] = createSignal<Payload | null>(null);
  const [columns, setColumns] = createSignal<string[]>([]);
  const [chosen, setChosen] = createSignal('');
  const [error, setError] = createSignal<string | null>(null);

  async function loadIR(variables: string[]) {
    const received = (await postRequest('get-card-ir', { variables }, null)) as Payload | null;
    if (!received) {
      setError('Could not reach DashiBoard. Is the server running?');
      return;
    }
    setError(null);
    setPayload(received);
    const types = Object.keys(received.cards).sort();
    if (!chosen() && types.length > 0) setChosen(types[0]);
  }

  onSettled(() => {
    // Card descriptions do not depend on the source, so the forms are usable before one is
    // connected; the variable pickers simply have nothing to offer until then.
    void loadIR([]);
  });

  async function connectSource(files: string | string[]) {
    const list = Array.isArray(files) ? files : [files];
    if (list.length === 0) return;
    const summaries = (await postRequest(
      'load-files',
      { name: 'source', files: list },
      null,
    )) as { name: string }[] | null;
    const names = (summaries ?? []).map((summary) => summary.name);
    setColumns(names);
    // Re-fetch so `$defs/variable` carries the real column enum rather than an empty one.
    await loadIR(names);
  }

  const cardTypes = () => Object.keys(payload()?.cards ?? {}).sort();

  const [result, setResult] = createSignal<RunResult | null>(null);
  const [running, setRunning] = createSignal(false);
  // Recomputed from the document, so the Run button reflects the current state rather than the
  // state at the last attempt.
  const blocked = () => runRequest().blocked;

  async function run() {
    const { request, blocked: why } = runRequest();
    if (why !== null) return; // the button is disabled; belt and braces
    setRunning(true);
    try {
      const received = (await postRequest('evaluate-pipeline', request, null)) as RunResult | null;
      setResult(received);
      if (!received) setError('The pipeline did not run. Check the server log.');
      else setError(null);
    } finally {
      setRunning(false);
    }
  }

  return (
    <main class="mx-auto max-w-5xl px-4 py-8">
      <Title>DashiBoard</Title>
      <h1 class="mb-6 text-3xl font-bold text-blue-900">DashiBoard</h1>

      <Show when={error()}>
        <p class="mb-4 rounded border border-red-200 bg-red-50 p-3 text-red-800">{error()}</p>
      </Show>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">1. Connect a source</h2>
        <FilePicker multiple onChange={(files) => void connectSource(files)} />
        <p class="text-sm text-gray-600">
          <Show when={columns().length > 0} fallback="No source connected — variable pickers will be empty.">
            {columns().length} columns: {columns().join(', ')}
          </Show>
        </p>
      </section>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">2. Add a card</h2>
        <Show when={payload()} fallback={<p class="text-gray-500">Loading card descriptions…</p>}>
          <div class="flex items-center gap-3">
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
      </section>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">3. Fill it in</h2>
        <Show
          when={document_store.state.nodes.length > 0}
          fallback={<p class="text-gray-500">No cards yet.</p>}
        >
          <For each={document_store.state.nodes}>
            {(node, index) => (
              <div class="my-4 rounded border border-gray-200 p-4">
                <div class="mb-2 flex items-center justify-between">
                  <span class="font-semibold text-blue-900">{String(node.card.type)}</span>
                  <Button danger onClick={() => removeNode(index())}>
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
        </Show>
      </section>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">4. Run it</h2>
        <Button
          disabled={running() || document_store.state.nodes.length === 0 || blocked() !== null}
          onClick={() => void run()}
        >
          {running() ? 'Running…' : 'Run pipeline'}
        </Button>
        <Show when={blocked()} keyed>
          {(why: string) => (
            <p class="mt-2 rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
              {why}
            </p>
          )}
        </Show>
        <Show when={result()} keyed>
          {(run_result: RunResult) => (
            <div class="mt-4">
              <Show when={run_result.graph} keyed>
                {(dot: string) => (
                  <div class="my-3">
                    <h3 class="text-sm font-semibold text-blue-800">Pipeline graph</h3>
                    <Graph dot={dot} />
                  </div>
                )}
              </Show>
              <h3 class="text-sm font-semibold text-blue-800">Report</h3>
              <pre data-testid="report" class="overflow-x-auto rounded bg-gray-50 p-3 text-xs">{
                JSON.stringify(run_result.report ?? null, null, 2)
              }</pre>
            </div>
          )}
        </Show>
      </section>

      <section>
        <h2 class="text-xl font-semibold text-blue-800">The document</h2>
        <p class="mb-2 text-sm text-gray-600">
          This is what would be saved — the authored config itself, not a reconstruction.
        </p>
        <pre
          data-testid="document"
          class="overflow-x-auto rounded bg-gray-50 p-3 text-xs"
        >{JSON.stringify(document_store.state, null, 2)}</pre>
      </section>
    </main>
  );
}
