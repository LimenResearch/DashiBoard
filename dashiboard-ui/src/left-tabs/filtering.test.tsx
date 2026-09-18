import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, fireEvent, waitFor } from '@solidjs/testing-library';
import { flush } from 'solid-js';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  downloadJSON: vi.fn(),
  setApiBase: vi.fn(),
  apiBase: () => '',
}));
// The picker's own tests cover choosing; here it hands back the one file there is.
vi.mock('../components/FilePicker', () => ({
  FilePicker: (props: { onChange?: (v: string) => void }) =>
    <button data-pick onClick={() => props.onChange?.('filters.json')}>pick</button>,
}));

import { Filters } from './filtering';
import { FILTERS_STORE, Interval } from '../stores';

const [filters, setFilters] = FILTERS_STORE;

beforeEach(() => {
  postRequest.mockReset();
  postRequest.mockImplementation(() => Promise.resolve([]));
  setFilters(() => ({ numerical: {}, categorical: {} }));
});
afterEach(cleanup);

describe('loading filters', () => {
  it('replaces the store with the document, its lists rebuilt into Sets', async () => {
    // A filters document is plain JSON: `{min,max}` and arrays, while the store holds `Set`s —
    // `getFilters` and the list filter call `Set` methods on them. The upload used to hand the
    // parsed JSON straight to the store, so a categorical filter arrived as an array. (An
    // `Interval` is not asserted by class: a Solid 2 store hands one back as a plain proxy
    // whichever way it is written — measured — and nothing reads it as more than `min`/`max`.)
    const saved = { numerical: { TEMP: { min: 0, max: 10 } }, categorical: { cbwd: ['NW', 'SE'] } };
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'read-document' ? { valid: true, document: saved } : []));
    const { container, getByText } = render(() => <Filters />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    await flush();
    fireEvent.click(getByText('Load filters'));
    await waitFor(() => expect(filters.numerical.TEMP).toBeDefined());
    expect(filters.numerical.TEMP?.min).toBe(0);
    expect(filters.numerical.TEMP?.max).toBe(10);
    expect(filters.categorical.cbwd).toBeInstanceOf(Set);
    expect([...filters.categorical.cbwd!]).toEqual(['NW', 'SE']);
  });

  it('saves the filters as plain JSON, which is what loads back', async () => {
    setFilters(() => ({ numerical: { TEMP: new Interval(0, 10) }, categorical: { cbwd: new Set(['NW']) } }));
    await flush();
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(page === 'write-document' ? { valid: true, path: 'filters.json' } : []));
    const { getByText } = render(() => <Filters />);
    fireEvent.click(getByText('Save filters'));
    await waitFor(() => expect(postRequest.mock.calls.some((c) => c[0] === 'write-document')).toBe(true));
    const sent = postRequest.mock.calls.find((c) => c[0] === 'write-document')![1] as { document: unknown };
    expect(sent.document).toEqual({ numerical: { TEMP: { min: 0, max: 10 } }, categorical: { cbwd: ['NW'] } });
  });
});

describe('filters dropped by a load', () => {
  it('are announced, and the notice closes', async () => {
    const { setDroppedFilters } = await import('../stores');
    setDroppedFilters(['cbwd', 'TEMP']);
    await flush();
    const { container } = render(() => <Filters />);
    const notice = container.querySelector('[data-dropped-filters]')!;
    expect(notice).not.toBeNull();
    expect(notice.textContent).toMatch(/not in the loaded table/);
    expect(notice.textContent).toMatch(/cbwd, TEMP/);
    fireEvent.click(notice.querySelector('button[aria-label="dismiss"]')!);
    await flush();
    expect(container.querySelector('[data-dropped-filters]')).toBeNull();
  });

  it('shows nothing when nothing was dropped', async () => {
    const { setDroppedFilters } = await import('../stores');
    setDroppedFilters([]);
    await flush();
    const { container } = render(() => <Filters />);
    expect(container.querySelector('[data-dropped-filters]')).toBeNull();
  });
});
