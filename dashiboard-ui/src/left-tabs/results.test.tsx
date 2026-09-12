import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush } from 'solid-js';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

import { Results } from './results';
import { importCards, emptyCards, type CardsStore } from '../stores';

/** Two nodes, so a per-node report has something to be paired with. */
const DOCUMENT: CardsStore = {
  nodes: [
    { id: 'rescaled', card: { type: 'rescale', method: { type: 'log' }, inputs: [{ cols: 'TEMP' }] } },
    { id: 'grouped', card: { type: 'cluster', method: { type: 'kmeans', classes: 2 } } },
  ],
  groups: {},
};

const RUN = {
  graph: 'digraph {a}',
  report: [{ rows: 60 }, {}],
  visualization: ['<svg data-one></svg>', null, '<svg data-two></svg>'],
  summaries: [
    { name: 'TEMP', type: 'numerical', eltype: 'float', summary: { min: -10, max: 29 } },
    { name: 'TEMP_rescaled', type: 'numerical', eltype: 'float', summary: { min: 0, max: 1 } },
  ],
};

/** Answer `evaluate-pipeline` with `result`, and everything else with something harmless. */
function serve(result: unknown = RUN) {
  postRequest.mockImplementation((page: string) => {
    if (page === 'evaluate-pipeline') return Promise.resolve(result);
    if (page === 'fetch-data') return Promise.resolve({ values: [], length: 0 });
    return Promise.resolve([]);
  });
}

const fetchCalls = () =>
  postRequest.mock.calls.filter((call: unknown[]) => call[0] === 'fetch-data');

async function runPipeline(getByText: (m: RegExp) => HTMLElement) {
  fireEvent.click(getByText(/run pipeline/i));
  await flush();
}

beforeEach(() => {
  importCards(structuredClone(DOCUMENT));
  postRequest.mockReset();
  serve();
});
afterEach(cleanup);

describe('Results', () => {
  it('shows nothing to read before a run', () => {
    const { container } = render(() => <Results />);
    expect(container.querySelector('[data-tabs="results"]')).toBeNull();
    expect(container.querySelector('.ag-theme-quartz')).toBeNull();
  });

  it('reads the pipeline output, not the source', async () => {
    // The whole point of this pane. `fetch-data` serves both tables and the only thing that
    // distinguishes them is this flag — the loader's preview passes `false`.
    const { getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(fetchCalls().length).toBeGreaterThan(0));
    expect(fetchCalls().every((call) => (call[1] as { processed: boolean }).processed)).toBe(true);
  });

  it('takes its columns from the run, which is where the pipeline output appears', async () => {
    // `evaluate-pipeline` recomputes `summaries` *after* the cards have run, so it carries the
    // columns they added. Taking them from LOADER_STORE instead would show the source's columns
    // and silently omit every result.
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('.ag-theme-quartz')).not.toBeNull());
    expect(container.textContent).toContain('TEMP_rescaled');
  });

  it('offers the output as a CSV, from the route that serves it', async () => {
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    const link = await waitFor(() => container.querySelector('a[download]') as HTMLAnchorElement);
    expect(link.getAttribute('href')).toBe('/get-processed-data');
  });

  it('renders each plot the run returned, and skips the cards that produced none', async () => {
    // `visualize` returns `nothing` for every card that does not override it, which serialises as
    // null — so most entries in this array are holes rather than plots.
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    fireEvent.click(container.querySelector('[data-tab="Plots"]')!);
    await flush();
    expect(container.querySelectorAll('[data-plot]')).toHaveLength(2);
    // As an image, not as markup spliced into the page. An `<img>` cannot run a script or fire an
    // event handler whatever the SVG contains, which `innerHTML` cannot promise — and the plot is
    // derived from the user's own column names, so its text is not fixed content.
    const plot = container.querySelector('[data-plot] img') as HTMLImageElement;
    expect(plot).not.toBeNull();
    expect(plot.getAttribute('src')).toMatch(/^data:image\/svg\+xml/);
    expect(decodeURIComponent(plot.getAttribute('src') ?? '')).toContain('data-one');
    expect(container.querySelector('[data-plot] svg')).toBeNull();
  });

  it('says so plainly when no card produced a plot', async () => {
    serve({ ...RUN, visualization: [null, null] });
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    fireEvent.click(container.querySelector('[data-tab="Plots"]')!);
    await flush();
    expect(container.querySelectorAll('[data-plot]')).toHaveLength(0);
    expect(container.textContent).toMatch(/no .*plot/i);
  });

  it('pairs each report with the node it describes', async () => {
    // `Pipelines.report` returns one entry per node, in document order, and nothing else. On its
    // own that is a list of anonymous dicts; against the document it is a per-card answer.
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    fireEvent.click(container.querySelector('[data-tab="Report"]')!);
    await flush();
    const named = [...container.querySelectorAll('[data-report]')].map((e) =>
      e.getAttribute('data-report'),
    );
    expect(named).toEqual(['rescaled', 'grouped']);
    expect(container.textContent).toContain('rows');
  });

  it('updates the output table in place rather than rebuilding it', async () => {
    // A keyed results block would replace the whole pane set on every run, which means recreating
    // the grid — and recreating it inside whichever pane is hidden at the time, where ag-grid has
    // no height to size itself against. Asserted on element identity, which is the thing that
    // differs; the rendered output looks the same either way.
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    const first = await waitFor(() => container.querySelector('.ag-theme-quartz')!);

    // The second run has to be *observed*, not merely fired: `flush()` settles the scheduler but
    // not the request promise, so without a visible difference to wait for this compared the
    // element against itself and passed whatever the block did. Measured — it did.
    serve({
      ...RUN,
      summaries: [...RUN.summaries, { name: 'extra', type: 'numerical', eltype: 'int', summary: { min: 0, max: 1 } }],
    });
    await runPipeline(getByText);
    await waitFor(() => expect(container.textContent).toContain('3 columns'));
    expect(container.querySelector('.ag-theme-quartz')).toBe(first);
  });

  it('keeps the open pane across a re-run', async () => {
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    fireEvent.click(container.querySelector('[data-tab="Graph"]')!);
    await flush();
    await runPipeline(getByText);
    const active = container.querySelector('[data-tabs="results"] [aria-selected="true"]');
    expect(active?.getAttribute('data-tab')).toBe('Graph');
  });

  it('sends the document the run needs, and nothing it does not', async () => {
    const { getByText } = render(() => <Results />);
    await runPipeline(getByText);
    const body = postRequest.mock.calls.find((c: unknown[]) => c[0] === 'evaluate-pipeline')![1];
    expect(Object.keys(body as object).sort()).toEqual(['filters', 'groups', 'nodes']);
  });
});
