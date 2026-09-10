import { createSignal, For, Show } from "solid-js";
import { Title } from "@solidjs/meta";

import { Button } from "../components/Button";
import { Graph } from "../components/Graph";
import { Loader } from "../left-tabs/loading";
import { Filters, getFilters } from "../left-tabs/filtering";
import { Cards, getCards } from "../left-tabs/processing";
import { postRequest } from "../requests";
import { CARDS_STORE, FILTERS_STORE } from "../stores";

type RunResult = { graph?: string; report?: unknown; summaries?: unknown };

const SECTIONS = ["Load", "Filter", "Process", "Run", "The document"] as const;

export default function Home() {
  const [filters] = FILTERS_STORE;
  const [cards] = CARDS_STORE;
  const [section, setSection] = createSignal<(typeof SECTIONS)[number]>("Load");

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
    <main class="mx-auto max-w-5xl px-4 py-2">
      <Title>DashiBoard</Title>

      {/*
        The five stages are tabs, not a single scroll. They are steps in one order — load, filter,
        process, run — and only one is being worked on at a time; stacked, the one in hand is
        wherever you last scrolled to.

        Every section stays mounted and is hidden rather than unmounted: Load sets up choices.js
        and Process fetches the card IR, so remounting on each switch would refetch and drop each
        picker's open tab. The stores survive either way — the local state is what would not.
      */}
      <div role="tablist" data-tabs="sections" class="mb-4 flex gap-1.5 border-b border-border">
        <For each={SECTIONS}>
          {(name) => (
            <button
              type="button"
              role="tab"
              aria-selected={section() === name ? "true" : "false"}
              onClick={() => {
                setSection(name);
              }}
              class={[
                "-mb-px rounded-t-sm border border-b-0 px-4 py-2 text-xs",
                {
                  "border-border bg-background font-semibold text-primary": section() === name,
                  "border-transparent text-muted-foreground hover:text-foreground": section() !== name,
                },
              ]}
            >
              {name}
            </button>
          )}
        </For>
      </div>

      <section data-section="Load" hidden={section() !== "Load"}>
        <Loader />
      </section>

      <section data-section="Filter" hidden={section() !== "Filter"}>
        <Filters />
      </section>

      <section data-section="Process" hidden={section() !== "Process"}>
        <Cards />
      </section>

      <section data-section="Run" hidden={section() !== "Run"}>
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
                class="overflow-x-auto rounded-sm bg-muted p-3 text-xs"
              >{JSON.stringify(res.report ?? null, null, 2)}</pre>
            </div>
          )}
        </Show>
      </section>

      <section data-section="The document" hidden={section() !== "The document"}>
        <pre
          data-testid="document"
          class="overflow-x-auto rounded-sm bg-muted p-3 text-xs"
        >{JSON.stringify({ filters: getFilters(filters), ...getCards(cards) }, null, 2)}</pre>
      </section>
    </main>
  );
}
