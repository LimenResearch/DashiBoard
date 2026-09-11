import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush } from 'solid-js';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

// FilePicker wraps choices.js, which does not drive in jsdom. The unit under test is Loader's
// load-and-store path, so the picker is replaced by a button that reports a selection.
vi.mock('../components/FilePicker', () => ({
  FilePicker: (props: { onChange?: (files: string[]) => void }) => (
    <button onClick={() => props.onChange?.(['sample.csv'])}>choose</button>
  ),
}));

import { Loader } from './loading';
import { LOADER_STORE, type LoaderStore } from '../stores';

const SUMMARIES: LoaderStore = [
  { name: 'No', type: 'numerical', eltype: 'int', summary: { min: 1, max: 60 } },
  { name: 'TEMP', type: 'numerical', eltype: 'float', summary: { min: -10, max: 29 } },
  { name: 'cbwd', type: 'categorical', eltype: 'string', summary: ['NW', 'SE'] },
];

beforeEach(() => {
  const [, setState] = LOADER_STORE;
  setState(() => []);
  postRequest.mockReset();
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
});
