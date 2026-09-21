import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush, snapshot } from 'solid-js';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

// FilePicker wraps choices.js, which does not drive in jsdom. The unit under test is Loader's
// load-and-store path, so the picker is replaced by a button that reports a selection.
vi.mock('../components/FilePicker', () => ({
  FilePicker: (props: { onChange?: (files: string[]) => void }) => (
    <button onClick={() => props.onChange?.(['sample.csv'])}>choose</button>
  ),
}));

import { Loader } from './loading';
import {
  LOADER_STORE, FILTERS_STORE, Interval, droppedFilters, setDroppedFilters, importCards, exportCards,
  droppedReferences, setDroppedReferences, type LoaderStore,
} from '../stores';
import { reconcile } from 'solid-js';

const SUMMARIES: LoaderStore = [
  { name: 'No', type: 'numerical', eltype: 'int', summary: { min: 1, max: 60 } },
  { name: 'TEMP', type: 'numerical', eltype: 'float', summary: { min: -10, max: 29 } },
  { name: 'cbwd', type: 'categorical', eltype: 'string', summary: ['NW', 'SE'] },
];

const num = (name: string): LoaderStore[number] => ({ name, type: 'numerical', eltype: 'float', summary: { min: 0, max: 1 } });

beforeEach(() => {
  const [, setState] = LOADER_STORE;
  setState(() => []);
  postRequest.mockReset();
  const [, setFilters] = FILTERS_STORE;
  setFilters(reconcile({ numerical: {}, categorical: {} }));
});
afterEach(cleanup);

describe('Loader', () => {
  it('puts the loaded column summaries into LOADER_STORE', async () => {
    // Everything downstream reads columns from here: the variable pickers' `cols` vocabulary and
    // the filter panels both. If this does not land, the UI simply has no columns.
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? SUMMARIES : ['sample.csv']),
    );

    const { getByText } = render(() => <Loader />);
    fireEvent.click(getByText('choose'));
    await flush();
    fireEvent.click(getByText(/^Load$/));

    const [state] = LOADER_STORE;
    await waitFor(() => expect(state.map((entry) => entry.name)).toEqual(['No', 'TEMP', 'cbwd']));
  });

  it('shows nothing to scroll until something is loaded', () => {
    postRequest.mockImplementation(() => Promise.resolve([]));
    const { container } = render(() => <Loader />);
    expect(container.querySelector('.ag-theme-quartz')).toBeNull();
  });

  it('previews the loaded source, so the column list is not the only evidence', async () => {
    postRequest.mockImplementation(() => Promise.resolve([]));
    const [, setState] = LOADER_STORE;
    setState(() => SUMMARIES);

    const { container } = render(() => <Loader />);
    await waitFor(() => expect(container.querySelector('.ag-theme-quartz')).not.toBeNull());
    expect(container.textContent).toContain('3 columns');
  });

  it('drops the filters the new table cannot apply, keeps the others, and reports the dropped', async () => {
    // Check 11 by hand: a list filter on `cbwd` survived loading a table with no `cbwd`, and the
    // run failed on it. A filter that cannot apply is dropped — and said, not silently.
    const [, setLoaderState] = LOADER_STORE;
    const [, setFilters] = FILTERS_STORE;
    setLoaderState(reconcile([num('TEMP'), num('cbwd')]));
    setFilters(reconcile({ numerical: { TEMP: new Interval(0, 1), cbwd: new Interval(0, 1) }, categorical: {} }));
    setDroppedFilters([]);
    await flush();

    // same columns → everything kept, nothing reported
    const served = [{ ...num('TEMP'), summary: { min: 0, max: 42 } }, num('cbwd')];
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? served : ['a.parquet']),
    );
    const { getByText } = render(() => <Loader />);
    fireEvent.click(getByText('choose'));
    await flush();
    fireEvent.click(getByText(/^Load$/));
    await waitFor(() => {
      expect((snapshot(LOADER_STORE[0])[0].summary as { max: number }).max).toBe(42);
    }, { timeout: 1000 });
    expect(Object.keys(snapshot(FILTERS_STORE[0]).numerical)).toEqual(['TEMP', 'cbwd']);
    expect(droppedFilters()).toEqual([]);

    // a table without cbwd → the cbwd filter is dropped and named; TEMP's stays
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? [num('TEMP'), num('No')] : ['a.parquet']),
    );
    await flush();
    fireEvent.click(getByText(/^Load$/));
    await waitFor(() => expect(droppedFilters()).toEqual(['cbwd']), { timeout: 1000 });
    expect(Object.keys(snapshot(FILTERS_STORE[0]).numerical)).toEqual(['TEMP']);
  });
});

describe('a load that orphans a card\'s reference', () => {
  it('removes the reference and says so', async () => {
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale', inputs: [{ cols: ['TEMP', 'GONE'] }] } }], groups: {} });
    setDroppedReferences([]);
    await flush();
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? [num('TEMP')] : ['a.parquet']),
    );
    const { getByText } = render(() => <Loader />);
    fireEvent.click(getByText('choose'));
    await flush();
    fireEvent.click(getByText(/^Load$/));
    await waitFor(() => expect(droppedReferences()).toEqual([{ what: 'cols:GONE', where: 'r' }]), { timeout: 1000 });
    expect(exportCards().nodes[0].card.inputs).toEqual([{ cols: 'TEMP' }]);
  });
});

describe('a second load whose columns summarise identically', () => {
  it('still refetches the preview: it is a different table', async () => {
    // A summary is a column's extrema or its distinct values, so two files with the same rows in
    // another order — or yesterday's export and today's — summarise identically. The preview's
    // revision was counted off the summaries alone, so the second load left the grid showing the
    // first file's rows (measured 2026-09-21, and seen in a browser with same-summary-A/B).
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'load-files' ? structuredClone(SUMMARIES)
        : page === 'fetch-data' ? { values: [], length: 0 } : ['sample.csv']));
    const fetches = () => postRequest.mock.calls.filter((c: unknown[]) => c[0] === 'fetch-data').length;
    const { getByText } = render(() => <Loader />);
    fireEvent.click(getByText('choose'));
    await flush();
    fireEvent.click(getByText('Load'));
    await waitFor(() => expect(fetches()).toBeGreaterThan(0));
    await new Promise((r) => setTimeout(r, 50));
    const afterFirst = fetches();
    fireEvent.click(getByText('Load'));
    await waitFor(() => expect(fetches()).toBeGreaterThan(afterFirst));
  });
});
