import { createSignal, For, Show } from "solid-js";

import { A, Button } from "../components/Button";
import { DownloadJSONButton } from "../components/JSON";
import { Graph } from "../components/Graph";
import { TableView } from "../components/TableView";
import { Tabs } from "../components/Tabs";
import { getURL, postRequest } from "../requests";
import { CARDS_STORE, type VariableSummary } from "../stores";
import { wireDocument } from "../wire";

// What a run produced (C4). Four answers to four different questions, so four panes rather than
// one scroll: the output table is what the pipeline *made*, the plots are what individual cards
// chose to draw, the graph is how the cards relate, and the report is what each card measured.
//
// `left-tabs/` is a holdover name — these are the page's sections, and §7 retires the folder along
// with the tabbed shell when the canvas lands. Kept here so all the sections stay in one place.

/** The shape of `POST /evaluate-pipeline`'s answer. Every field is optional: an older server, or
 *  a failed request, must degrade to an empty pane rather than a crash. */
type RunResult = {
  /** `false` when the run threw. Absent from a server predating the change, which then reads as
   *  success — the same degradation the probe's `issues` field takes. */
  valid?: boolean;
  /** Where it broke: `"pipeline"` before anything ran, `"execution"` while running. */
  kind?: string;
  errors?: string[];
  graph?: string;
  report?: unknown[];
  /** One entry per node, `null` for every card that does not override `Pipelines.visualize`. */
  visualization?: (string | null)[];
  /** Recomputed *after* the cards run, so it carries the columns they added. */
  summaries?: VariableSummary[];
};

const PANES = ["Table", "Plots", "Graph", "Report"] as const;
type Pane = (typeof PANES)[number];

export function Results() {
  const [cards] = CARDS_STORE;
  const [result, setResult] = createSignal<RunResult | null>(null);
  const [running, setRunning] = createSignal(false);
  /**
   * How many runs have landed — the table's `revision`.
   *
   * A second run produces new rows behind columns that are usually the *same* columns, and the
   * grid pages through `fetch-data` rather than holding them, so nothing in `summaries()` tells
   * it that what it cached is now the previous run's output. Counting the runs does.
   */
  const [runs, setRuns] = createSignal(0);
  /**
   * Why the last run produced nothing to look at.
   *
   * Held apart from `result`, which therefore only ever holds a run that succeeded — so every pane
   * below can read it without asking whether it is real. The distinction the reader needs is
   * between "not run yet" and "run, and it failed", and a single nullable result cannot make it:
   * both are `null`.
   */
  const [failure, setFailure] = createSignal<{ kind?: string; errors: string[] } | null>(null);

  /**
   * What the reader should do about it, which is the one thing the server's message cannot say.
   *
   * The two kinds call for opposite responses — a document that could not be built is fixed in
   * the form above, a run that died is fixed in the data — so saying which is worth a line. An
   * unrecognised or absent `kind` says nothing rather than guessing.
   */
  const HEADINGS: Record<string, string> = {
    pipeline: "DashiBoard could not build this pipeline — the definition is at fault.",
    execution: "The pipeline ran and failed — the definition is fine, the data or the run is not.",
  };
  // Held outside the results block, and the block is updated rather than replaced, so a re-run
  // leaves the reader on the pane they were reading.
  const [pane, setPane] = createSignal<Pane>("Table");

  async function run() {
    setRunning(true);
    try {
      const answer = (await postRequest("evaluate-pipeline", wireDocument(), null)) as
        | RunResult
        | null;
      // `postRequest` collapses a dead server, a non-JSON body and a network fault alike into the
      // default it was given. Whatever the cause, the reader must not be left thinking the run
      // succeeded — which is what an unchanged screen says.
      if (answer === null) {
        setResult(null);
        setFailure({ errors: ["Could not reach DashiBoard. Is the server running?"] });
        return;
      }
      if (answer.valid === false) {
        setResult(null);
        setFailure({
          kind: answer.kind,
          errors: answer.errors?.length ? answer.errors : ["The run failed, without saying why."],
        });
        return;
      }
      setFailure(null);
      setResult(answer);
      setRuns((n) => n + 1);
    } finally {
      setRunning(false);
    }
  }

  /**
   * The output table's columns come from the run, not from `LOADER_STORE`.
   *
   * `evaluate-pipeline` recomputes `summarize` after the pipeline has run — the handler says so —
   * so this list carries every column the cards added. The loader's list is the *source*, and
   * using it here would silently omit exactly the columns someone ran the pipeline to see.
   */
  const summaries = (): VariableSummary[] => result()?.summaries ?? [];

  /**
   * A finished SVG, as an image rather than as markup spliced into the page.
   *
   * The server sends `show(MIME"image/svg+xml")` of whatever a card's `visualize` returned, so the
   * plot's text is derived from the user's own column names rather than being fixed content.
   * `innerHTML` would put that in the document: it will not run a `<script>`, but an SVG can carry
   * event attributes, and it is not this component's place to reason about what Cairo escapes. An
   * `<img>` cannot execute anything whatever the bytes contain, which is a boundary rather than an
   * argument — and a plot needs nothing an image cannot do.
   *
   * Percent-encoded, not base64: `btoa` throws on any character outside Latin-1, which a column
   * name is free to contain.
   */
  const svgSource = (svg: string) =>
    `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;

  /** Only the entries that are plots. Most cards draw nothing and serialise as `null`. */
  const plots = (): string[] =>
    (result()?.visualization ?? []).filter((item): item is string => typeof item === "string");

  /**
   * Each report against the node it describes.
   *
   * `Pipelines.report` returns one entry per node in document order and nothing else, so on its
   * own it is a list of anonymous dicts. Paired with the document it becomes a per-card answer —
   * which is the same pairing the retired `spreadsheet.jsx` did before downloading it.
   */
  const reports = () =>
    (result()?.report ?? []).map((report, index) => ({
      id: cards.nodes[index]?.id || `node ${index + 1}`,
      report,
    }));

  const empty = (message: string) => (
    <p class="p-3 text-control-xs text-muted-foreground italic">{message}</p>
  );

  return (
    <div>
      <div class="flex items-center gap-2 p-3">
        <Button disabled={running() || cards.nodes.length === 0} onClick={() => void run()}>
          {running() ? "Running…" : "Run pipeline"}
        </Button>
        <Show when={cards.nodes.length === 0}>
          <span class="text-control-xs text-muted-foreground">Add a card first.</span>
        </Show>
      </div>

      {/*
        Destructive styling, not the warning used for an unfinished card: this one already ran and
        did not work. The text is the server's own — `showerror` on whatever Julia threw — because
        a paraphrase of an error nobody anticipated is worth less than the error.
      */}
      <Show when={failure()} keyed>
        {(f: { kind?: string; errors: string[] }) => (
          <div
            data-run-error={f.kind ?? ""}
            class="mx-3 mb-2 rounded-sm border border-destructive/30 bg-destructive/10 p-3 text-control-xs text-destructive"
          >
            <Show when={f.kind !== undefined && HEADINGS[f.kind]}>
              <p class="mb-1.5 font-semibold">{HEADINGS[f.kind!]}</p>
            </Show>
            <For each={f.errors}>
              {(line: string) => <p class="font-mono break-words">{line}</p>}
            </For>
          </div>
        )}
      </Show>

      {/* Updated in place rather than keyed: a keyed block would rebuild the grid on every run,
          and it would rebuild it inside whichever pane is hidden at the time — where ag-grid has
          no height to size itself against. */}
      <Show when={result()}>
        <div class="mt-2">
          <Tabs group="results" items={PANES} active={pane()} onSelect={setPane} />

          <div data-pane="Table" hidden={pane() !== "Table"}>
            <Show when={summaries().length > 0} fallback={empty("The run reported no columns.")}>
              <div class="p-3">
                <p class="mb-1.5 text-detail tracking-wider text-muted-foreground uppercase">
                  {summaries().length} columns
                </p>
                {/* Paged through `fetch-data`, so this stays usable on an output larger than the
                    browser — the same reason the loader previews the source this way. */}
                <TableView processed revision={runs()} metadata={summaries()} class="h-96" />
                <div class="mt-3">
                  <A href={getURL("get-processed-data")} download="processed-data.csv">
                    Download CSV
                  </A>
                </div>
              </div>
            </Show>
          </div>

          <div data-pane="Plots" hidden={pane() !== "Plots"}>
            <For each={plots()} fallback={empty("No card in this pipeline drew a plot.")}>
              {(svg: string) => (
                <div data-plot class="overflow-x-auto p-3">
                  <img src={svgSource(svg)} alt="" class="max-w-full" />
                </div>
              )}
            </For>
          </div>

          <div data-pane="Graph" hidden={pane() !== "Graph"}>
            <Show when={result()?.graph} fallback={empty("The run returned no graph.")} keyed>
              {(dot: string) => (
                <div class="p-3">
                  <Graph dot={dot} />
                </div>
              )}
            </Show>
          </div>

          {/* `data-testid` kept: the page-level run test reads the report to know a run landed. */}
          <div data-pane="Report" data-testid="report" hidden={pane() !== "Report"}>
            <div class="p-3">
              <For each={reports()} fallback={empty("The run reported nothing.")}>
                {(entry: { id: string; report: unknown }) => (
                  <div data-report={entry.id} class="mb-2">
                    <p class="font-mono text-control-xs font-semibold text-primary">{entry.id}</p>
                    <pre class="overflow-x-auto rounded-sm bg-muted p-2 text-control-xs">
                      {JSON.stringify(entry.report ?? null, null, 2)}
                    </pre>
                  </div>
                )}
              </For>
              <DownloadJSONButton data={reports()} name="report.json">
                Download report
              </DownloadJSONButton>
            </div>
          </div>
        </div>
      </Show>
    </div>
  );
}
