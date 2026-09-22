import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';
import { createSignal, flush, untrack } from 'solid-js';

const postRequest = vi.fn();
const downloadJSON = vi.fn();
const refreshed = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  downloadJSON: (...args: unknown[]) => downloadJSON(...args),
  getURL: (page: string) => `/${page}`,
  setApiBase: vi.fn(), apiBase: () => '',
}));
// The real picker is a Choices.js widget; what matters here is which path it hands back.
vi.mock('./FilePicker', () => ({
  FilePicker: (props: { kind: string; onChange?: (v: string) => void; refreshRef?: (f: () => void) => void }) => {
    untrack(() => props.refreshRef)?.(() => refreshed());
    return <button data-pick onClick={() => props.onChange?.(`sub/${props.kind}.json`)}>pick</button>;
  },
}));

import { Documents } from './Documents';

const CARDS = { nodes: [{ id: 'r', card: { type: 'rescale' } }], groups: {} };
const serve = (replies: Record<string, unknown>) =>
  postRequest.mockImplementation((page: string) => Promise.resolve(replies[page] ?? null));

beforeEach(() => { postRequest.mockReset(); downloadJSON.mockReset(); refreshed.mockReset(); });
afterEach(cleanup);

describe('Documents', () => {
  it('loads the picked file through the server and hands the document to its owner', async () => {
    serve({ 'read-document': { valid: true, document: CARDS } });
    const onLoad = vi.fn(() => Promise.resolve([]));
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={onLoad} />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    await flush();            // two actions by a user are two ticks; Solid 2 stages a write until then
    fireEvent.click(getByText('Load cards'));
    await waitFor(() => expect(onLoad).toHaveBeenCalledWith(CARDS));
    expect(postRequest).toHaveBeenCalledWith('read-document', { path: 'sub/cards.json', kind: 'cards' }, null);
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it("calls the document by another name on its buttons, and keeps the server's kind on the wire", async () => {
    serve({ 'read-document': { valid: true, document: CARDS } });
    const { container, getByText } = render(() => (
      <Documents kind="cards" noun="pipeline" document={() => CARDS} onLoad={() => Promise.resolve([])} />
    ));
    expect(getByText('Save pipeline')).toBeDefined();
    expect(getByText('Download pipeline')).toBeDefined();
    expect((container.querySelector('input[aria-label="file name"]') as HTMLInputElement).value).toBe('pipeline.json');
    fireEvent.click(container.querySelector('[data-pick]')!);
    await flush();
    fireEvent.click(getByText('Load pipeline'));
    await waitFor(() => expect(postRequest).toHaveBeenCalledWith('read-document', { path: 'sub/cards.json', kind: 'cards' }, null));
  });

  it('cannot load before a file is picked', () => {
    const { getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={() => []} />);
    expect((getByText('Load cards') as HTMLButtonElement).disabled).toBe(true);
  });

  it('shows the server\'s sentence when a load fails, and loads nothing', async () => {
    serve({ 'read-document': { valid: false, kind: 'document', errors: ['`x.json` is not a cards document'], issues: [] } });
    const onLoad = vi.fn(() => []);
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={onLoad} />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    await flush();            // two actions by a user are two ticks; Solid 2 stages a write until then
    fireEvent.click(getByText('Load cards'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toContain('is not a cards document');
    expect(onLoad).not.toHaveBeenCalled();
  });

  it('says so when the server cannot be reached', async () => {
    serve({});
    const { container, getByText } = render(() => <Documents kind="filters" document={() => ({})} onLoad={() => []} />);
    fireEvent.click(container.querySelector('[data-pick]')!);
    await flush();            // two actions by a user are two ticks; Solid 2 stages a write until then
    fireEvent.click(getByText('Load filters'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toMatch(/could not reach/i);
  });

  it('shows what the loader could not place, and clears it when the document is edited', async () => {
    serve({ 'read-document': { valid: true, document: CARDS } });
    const [doc, setDoc] = createSignal<unknown>(CARDS);
    const { container, getByText } = render(() => (
      <Documents kind="cards" document={doc} onLoad={() => Promise.resolve(['The input graph contains at least one loop.'])} />
    ));
    fireEvent.click(container.querySelector('[data-pick]')!);
    await flush();            // two actions by a user are two ticks; Solid 2 stages a write until then
    fireEvent.click(getByText('Load cards'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toContain('at least one loop');
    setDoc({ ...CARDS, nodes: [] });
    await flush();
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it('saves the document under the name given, and re-lists', async () => {
    serve({ 'write-document': { valid: true, path: 'mine.json' } });
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={() => []} />);
    const name = container.querySelector('input[aria-label="file name"]') as HTMLInputElement;
    expect(name.value).toBe('cards.json');
    name.value = 'mine.json';
    fireEvent.change(name);
    await flush();
    fireEvent.click(getByText('Save cards'));
    await waitFor(() => expect(refreshed).toHaveBeenCalled());
    expect(postRequest).toHaveBeenCalledWith(
      'write-document', { path: 'mine.json', kind: 'cards', document: CARDS, overwrite: false }, null,
    );
  });

  it('replaces an existing file only when the author says so', async () => {
    serve({ 'write-document': { valid: false, kind: 'document', errors: ['`cards.json` already exists'], issues: [] } });
    const { container, getByText } = render(() => <Documents kind="cards" document={() => CARDS} onLoad={() => []} />);
    fireEvent.click(getByText('Save cards'));
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toContain('already exists');
    expect(refreshed).not.toHaveBeenCalled();

    serve({ 'write-document': { valid: true, path: 'cards.json' } });
    fireEvent.click(container.querySelector('input[type="checkbox"]')!);
    await flush();
    fireEvent.click(getByText('Save cards'));
    await waitFor(() => expect(refreshed).toHaveBeenCalled());
    expect(postRequest.mock.calls.at(-1)![1]).toMatchObject({ overwrite: true });
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it('downloads exactly what it saves', () => {
    const { getByText } = render(() => <Documents kind="filters" document={() => ({ numerical: {}, categorical: { cbwd: ['NW'] } })} onLoad={() => []} />);
    fireEvent.click(getByText('Download filters'));
    expect(downloadJSON.mock.calls[0][0]).toEqual({ numerical: {}, categorical: { cbwd: ['NW'] } });
  });
});
