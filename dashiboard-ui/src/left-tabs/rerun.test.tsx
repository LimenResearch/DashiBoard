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
import { Loader } from './loading';
import { importCards, LOADER_STORE, type CardsStore } from '../stores';

// The grid is an infinite row model: it pages through a datasource and caches the blocks it got.
// A column change does not clear that cache — only a new datasource does — so what these tests
// watch is whether new rows behind the same columns are actually asked for again. The evidence is
// the `fetch-data` count: if it does not rise, the reader is looking at the previous run's rows.

const DOCUMENT: CardsStore = {
  nodes: [{ id: 'rescaled', card: { type: 'rescale', method: { type: 'log' }, inputs: [{ cols: 'TEMP' }] } }],
  groups: {},
};
const RUN = {
  graph: 'digraph {a}', report: [{ rows: 60 }], visualization: [null],
  summaries: [
    { name: 'TEMP', type: 'numerical', eltype: 'float', summary: { min: -10, max: 29 } },
  ],
};
// Non-empty rows, so block 0 is a real loaded block rather than an empty table.
const ROWS = { values: [{ TEMP: 1, extra: 9 }, { TEMP: 2, extra: 8 }, { TEMP: 3, extra: 7 }], length: 3 };
function serve(result: unknown = RUN) {
  postRequest.mockImplementation((page: string) => {
    if (page === 'evaluate-pipeline') return Promise.resolve(result);
    if (page === 'fetch-data') return Promise.resolve(ROWS);
    return Promise.resolve([]);
  });
}
const fetchCalls = () => postRequest.mock.calls.filter((c: unknown[]) => c[0] === 'fetch-data');

beforeEach(() => {
  sessionStorage.clear();
  importCards(structuredClone(DOCUMENT));
  postRequest.mockReset();
  serve();
});
afterEach(cleanup);

describe('the grid refetches when the data behind it changes', () => {
  it('results: a second successful run with new columns asks fetch-data again', async () => {
    const { getByText, container } = render(() => <Results />);
    fireEvent.click(getByText(/run pipeline/i)); await flush();
    await waitFor(() => expect(fetchCalls().length).toBeGreaterThan(0));
    await new Promise((r) => setTimeout(r, 50)); await flush();
    const afterFirst = fetchCalls().length;
    serve({ ...RUN, summaries: [...RUN.summaries, { name: 'extra', type: 'numerical', eltype: 'int', summary: { min: 0, max: 1 } }] });
    fireEvent.click(getByText(/run pipeline/i)); await flush();
    await waitFor(() => expect(container.textContent).toContain('2 columns'));
    await new Promise((r) => setTimeout(r, 100)); await flush();
    expect(fetchCalls().length).toBeGreaterThan(afterFirst);
  });

  it('results: a second run with the SAME columns asks fetch-data again', async () => {
    const { getByText } = render(() => <Results />);
    fireEvent.click(getByText(/run pipeline/i)); await flush();
    await waitFor(() => expect(fetchCalls().length).toBeGreaterThan(0));
    await new Promise((r) => setTimeout(r, 50)); await flush();
    const afterFirst = fetchCalls().length;
    serve({ ...RUN, report: [{ rows: 61 }] });
    fireEvent.click(getByText(/run pipeline/i)); await flush();
    await new Promise((r) => setTimeout(r, 100)); await flush();
    expect(fetchCalls().length).toBeGreaterThan(afterFirst);
  });

  it('loader: loading a second source with different columns asks fetch-data again', async () => {
    const [, setState] = LOADER_STORE;
    setState(reconcile([]));
    await flush();
    render(() => <Loader />);
    setState(reconcile([{ name: 'A', type: 'numerical', eltype: 'float', summary: { min: 0, max: 1 } }]));
    await flush();
    await waitFor(() => expect(fetchCalls().length).toBeGreaterThan(0));
    await new Promise((r) => setTimeout(r, 50)); await flush();
    const afterFirst = fetchCalls().length;
    setState(reconcile([{ name: 'B', type: 'numerical', eltype: 'float', summary: { min: 0, max: 1 } }, { name: 'C', type: 'categorical', eltype: 'string', summary: [] }]));
    await flush();
    await new Promise((r) => setTimeout(r, 100)); await flush();
    expect(fetchCalls().length).toBeGreaterThan(afterFirst);
  });

  it('loader: loading a second source with the SAME columns asks fetch-data again', async () => {
    const [, setState] = LOADER_STORE;
    setState(reconcile([]));
    await flush();
    render(() => <Loader />);
    setState(reconcile([{ name: 'A', type: 'numerical', eltype: 'float', summary: { min: 0, max: 1 } }]));
    await flush();
    await waitFor(() => expect(fetchCalls().length).toBeGreaterThan(0));
    await new Promise((r) => setTimeout(r, 50)); await flush();
    const afterFirst = fetchCalls().length;
    setState(reconcile([{ name: 'A', type: 'numerical', eltype: 'float', summary: { min: 5, max: 9 } }]));
    await flush();
    await new Promise((r) => setTimeout(r, 100)); await flush();
    expect(fetchCalls().length).toBeGreaterThan(afterFirst);
  });
});
