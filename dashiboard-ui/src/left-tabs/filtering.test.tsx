import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';

const loadJSON = vi.fn();
vi.mock('../requests', () => ({
  postRequest: vi.fn(() => Promise.resolve([])),
  getURL: (page: string) => `/${page}`,
  loadJSON: (...args: unknown[]) => loadJSON(...args),
  downloadJSON: vi.fn(),
  setApiBase: vi.fn(),
  apiBase: () => '',
}));

import { Filters } from './filtering';
import { FILTERS_STORE, Interval } from '../stores';

const [filters, setFilters] = FILTERS_STORE;

beforeEach(() => {
  loadJSON.mockReset();
  setFilters(() => ({ numerical: {}, categorical: {} }));
});
afterEach(cleanup);

describe('uploading filters', () => {
  it('replaces the store with what was uploaded', async () => {
    // A Solid 2 store setter takes a *function*. `onChange={setFilters}` handed it the parsed
    // object, so the upload silently did nothing — the same contract that has bitten the load
    // path, the probe and the group editor.
    const uploaded = { numerical: { TEMP: new Interval(0, 10) }, categorical: {} };
    loadJSON.mockImplementation(() => Promise.resolve(uploaded));

    const { container } = render(() => <Filters />);
    const fileInput = container.querySelector('input[type=file]')!;
    fireEvent.change(fileInput);

    await waitFor(() => expect(filters.numerical.TEMP).toBeDefined());
    expect(filters.numerical.TEMP?.min).toBe(0);
    expect(filters.numerical.TEMP?.max).toBe(10);
  });
});
