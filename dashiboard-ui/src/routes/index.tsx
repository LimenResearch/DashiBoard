import { createSignal, Show } from "solid-js";
import { Title } from "@solidjs/meta";

import { Button } from "../components/Button";
import { Graph } from "../components/Graph";
import { Loader } from "../left-tabs/loading";
import { Filters, getFilters } from "../left-tabs/filtering";
import { Cards, getCards } from "../left-tabs/processing";
import { postRequest } from "../requests";
import { CARDS_STORE, FILTERS_STORE } from "../stores";

type RunResult = { graph?: string; report?: unknown; summaries?: unknown };

export default function Home() {
  const [filters] = FILTERS_STORE;
  const [cards] = CARDS_STORE;

  const [result, setResult] = createSignal<RunResult | null>(null);
  const [running, setRunning] = createSignal(false);

  async function run() {
    setRunning(true);
    try {
      // `{filters, nodes, groups}` — the group dialect the server now runs. Assembled from the
      // two stores by their own getters, rather than held in a third place.
      const body = { filters: getFilters(filters), ...getCards(cards) };
      setResult((await postRequest("evaluate-pipeline", body, null)) as RunResult | null);
    } finally {
      setRunning(false);
    }
  }

  return (
    <main class="mx-auto max-w-5xl px-4 py-8">
      <Title>DashiBoard</Title>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">Load</h2>
        <Loader />
      </section>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">Filter</h2>
        <Filters />
      </section>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">Process</h2>
        <Cards />
      </section>

      <section class="mb-8">
        <h2 class="text-xl font-semibold text-blue-800">Run</h2>
        <Button disabled={running() || cards.nodes.length === 0} onClick={() => void run()}>
          {running() ? "Running…" : "Run pipeline"}
        </Button>
        <Show when={result()} keyed>
          {(res: RunResult) => (
            <div class="mt-4">
              <Show when={res.graph} keyed>
                {(dot: string) => <Graph dot={dot} />}
              </Show>
              <pre
                data-testid="report"
                class="overflow-x-auto rounded bg-gray-50 p-3 text-xs"
              >{JSON.stringify(res.report ?? null, null, 2)}</pre>
            </div>
          )}
        </Show>
      </section>

      <section>
        <h2 class="text-xl font-semibold text-blue-800">The document</h2>
        <pre
          data-testid="document"
          class="overflow-x-auto rounded bg-gray-50 p-3 text-xs"
        >{JSON.stringify({ filters: getFilters(filters), ...getCards(cards) }, null, 2)}</pre>
      </section>
    </main>
  );
}
