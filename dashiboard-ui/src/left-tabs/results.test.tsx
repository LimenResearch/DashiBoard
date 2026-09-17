import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush, reconcile } from 'solid-js';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

import { Results } from './results';
import {
  importCards, forgetAllVerdicts, verdictOf, exportCards, PROBE_STORE, emptyProbe, type CardsStore,
} from '../stores';

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
  sessionStorage.clear();
  importCards(structuredClone(DOCUMENT));
  // Module-level state a test here seeds (a failed run's issues, a verdict) must not leak into
  // the next render — the same resets `processing.test.tsx` and `GroupsEditor.test.tsx` make.
  PROBE_STORE[1](reconcile(emptyProbe()));
  forgetAllVerdicts();
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

  it('shows what the server said when the run failed', async () => {
    // The gap this closes: a run that the schema accepts and the data defeats — PCA asked for more
    // components than there are columns — used to leave the screen completely unchanged. The
    // button went back to "Run pipeline" and nothing else happened, which reads as "nothing
    // occurred" rather than "it failed".
    serve({
      valid: false,
      errors: ['Binder Error: MethodError: no method matching add_result_column'],
      issues: [],
    });
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(container.textContent).toContain('Binder Error');
    // and no panes, because there is no result to look at
    expect(container.querySelector('[data-tabs="results"]')).toBeNull();
    expect(container.querySelector('.ag-theme-quartz')).toBeNull();
  });

  it('sends the reader to the cards or to the data, depending on where it broke', async () => {
    // `kind` is the only thing that distinguishes these two, and they call for opposite responses:
    // a document that could not be built is fixed in the form, a run that died is fixed in the
    // data. The server's own text is shown either way — it is the part nobody could have written
    // in advance.
    serve({ valid: false, kind: 'pipeline', errors: ['duplicate id ""'], issues: [] });
    const { container, getByText, unmount } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(container.querySelector('[data-run-error]')!.getAttribute('data-run-error')).toBe('pipeline');
    expect(container.textContent).toMatch(/could not build/i);
    expect(container.textContent).toContain('duplicate id');
    unmount();

    serve({ valid: false, kind: 'execution', errors: ['Binder Error'], issues: [] });
    const second = render(() => <Results />);
    await runPipeline(second.getByText);
    await waitFor(() =>
      expect(second.container.querySelector('[data-run-error]')).not.toBeNull(),
    );
    expect(second.container.querySelector('[data-run-error]')!.getAttribute('data-run-error'))
      .toBe('execution');
    expect(second.container.textContent).toMatch(/ran and failed/i);
  });

  it('says so when the server answers nothing at all', async () => {
    // `postRequest` collapses a dead server, a non-JSON body and a network fault into `null`.
    // Whatever the cause, the one thing the reader must not conclude is that the run succeeded.
    postRequest.mockImplementation(() => Promise.resolve(null));
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(container.textContent).toMatch(/could not reach/i);
  });

  it('clears a previous failure once a run succeeds', async () => {
    serve({ valid: false, errors: ['boom'], issues: [] });
    const { container, getByText } = render(() => <Results />);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());

    serve(RUN);
    await runPipeline(getByText);
    await waitFor(() => expect(container.querySelector('[data-tabs="results"]')).not.toBeNull());
    expect(container.querySelector('[data-run-error]')).toBeNull();
  });

  it('sends the document the run needs, and nothing it does not', async () => {
    const { getByText } = render(() => <Results />);
    await runPipeline(getByText);
    const body = postRequest.mock.calls.find((c: unknown[]) => c[0] === 'evaluate-pipeline')![1];
    expect(Object.keys(body as object).sort()).toEqual(['filters', 'groups', 'nodes']);
  });
});

describe('a run that failed to build', () => {
  it('puts the server\'s issues on the cards and names the count', async () => {
    // Check 12 by hand: two incomplete cards, Run → the pane showed JSONSchema.jl's raw text
    // while Confirm on the same card showed two field pointers. Same fault, one rendering.
    importCards({ nodes: [{ id: 'a', card: { type: 'cluster' } }, { id: 'b', card: { type: 'split' } }], groups: {} });
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'evaluate-pipeline'
        ? { valid: false, kind: 'pipeline', errors: ['2 schema validation errors: …'],
            issues: [
              { pointer: '/nodes/0/card', reason: 'required', severity: 'error', found: null, allowed: null, missing: ['method', 'inputs'], related: ['/nodes/0/card/method', '/nodes/0/card/inputs'], message: 'x' },
              { pointer: '/nodes/1/card', reason: 'required', severity: 'error', found: null, allowed: null, missing: ['method'], related: ['/nodes/1/card/method'], message: 'y' },
            ] }
        : []));
    const { container, getByText } = render(() => <Results />);
    fireEvent.click(getByText(/run pipeline/i));
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(container.querySelector('[data-run-error]')!.textContent).toMatch(/2 cards need attention/);
    expect(PROBE_STORE[0].issues.map((i) => i.pointer)).toEqual(['/nodes/0/card', '/nodes/1/card']);
    // A Run is the author asking: each pointed card is now rejected, with the run's findings.
    await flush();
    const nodes = exportCards().nodes;
    expect(verdictOf('node:0', nodes[0])?.verdict).toBe('rejected');
    expect(verdictOf('node:0', nodes[0])?.findings.map((f) => f.pointer)).toEqual(['/nodes/0/card/method', '/nodes/0/card/inputs']);
    expect(verdictOf('node:1', nodes[1])?.verdict).toBe('rejected');
    // And the pointer next to Run names both.
    expect(container.querySelector('[data-needs-attention]')!.textContent).toMatch(/a, b/);
  });

  it('counts a group issue as a group, not a card', async () => {
    // `/groups/g` is not `/nodes/<i>/card`: counting pointer segment 2 whatever segment 1 said
    // put an empty-group failure on the card count, with nothing on screen to show for it.
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'evaluate-pipeline'
        ? { valid: false, kind: 'pipeline', errors: ['group `g` has no columns'],
            issues: [
              { pointer: '/groups/g', reason: 'empty', severity: 'error', found: null, allowed: null, missing: [], related: [], message: 'group `g` has no columns' },
            ] }
        : []));
    const { container, getByText } = render(() => <Results />);
    fireEvent.click(getByText(/run pipeline/i));
    await waitFor(() => expect(container.querySelector('[data-run-error]')).not.toBeNull());
    expect(container.querySelector('[data-run-error]')!.textContent).toMatch(/1 group needs attention/);
    expect(container.querySelector('[data-run-error]')!.textContent).not.toMatch(/card/);
  });
});

describe('the pointer next to Run pipeline', () => {
  const issue = (pointer: string, severity: 'error' | 'warning' = 'error') => ({
    pointer, reason: 'required', severity, found: null, allowed: null, missing: [], related: [], message: 'x',
  });

  it('names the items the probe objects to, and nothing when it is valid', async () => {
    importCards({
      nodes: [{ id: 'cluster', card: { type: 'cluster' } }, { card: { type: 'split' } }],
      groups: { group_2: [] },
    });
    PROBE_STORE[1]((d) => {
      d.valid = false;
      d.issues = [
        issue('/nodes/0/card'),
        issue('/nodes/0/card/method'),          // a second issue on the same card: named once
        issue('/nodes/1/card'),
        issue('/groups/group_2'),
        issue('/nodes/1/card', 'warning'),      // a warning is not an objection
      ];
    });
    await flush();
    const { container } = render(() => <Results />);
    const pointer = container.querySelector('[data-needs-attention]');
    expect(pointer).not.toBeNull();
    expect(pointer!.textContent).toMatch(/Needs attention: cluster, card 2, group_2/);
    expect(pointer!.className).toMatch(/destructive/);
    PROBE_STORE[1]((d) => { d.valid = true; d.issues = []; });
    await flush();
    expect(container.querySelector('[data-needs-attention]')).toBeNull();
  });

  it('names only the items the errors point at, when a warning is the only issue', async () => {
    PROBE_STORE[1]((d) => { d.valid = true; d.issues = [issue('/nodes/0/card', 'warning')]; });
    await flush();
    const { container } = render(() => <Results />);
    expect(container.querySelector('[data-needs-attention]')).toBeNull();
  });

  it('says "the document" for a fault with no item pointer', async () => {
    PROBE_STORE[1]((d) => { d.valid = false; d.issues = []; d.errors = ['Encountered nodes with equal `id`']; });
    await flush();
    const { container } = render(() => <Results />);
    expect(container.querySelector('[data-needs-attention]')!.textContent).toMatch(/Needs attention: the document/);
  });
});
