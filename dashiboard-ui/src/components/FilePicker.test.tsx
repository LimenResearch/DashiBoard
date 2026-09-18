import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(),
  downloadJSON: vi.fn(),
  setApiBase: vi.fn(),
  apiBase: () => '',
}));

import { FilePicker } from './FilePicker';

// What `list-files` answers: every file the UI may pick, with what it is. One listing serves
// three pickers, so each test says which kind it is looking through.
const LISTING = [
  { path: 'a.parquet', kind: 'table' },
  { path: 'b.parquet', kind: 'table' },
  { path: 'cards.json', kind: 'cards' },
  { path: 'sub/filters.json', kind: 'filters' },
];
beforeEach(() => {
  postRequest.mockReset();
  postRequest.mockImplementation(() => Promise.resolve(LISTING));
});
afterEach(cleanup);

describe('FilePicker', () => {
  it('offers the paths the server returns', async () => {
    // `postRequest` is a promise. Whether a plain `createMemo` over one yields the value or the
    // promise itself decides whether `options()` can map over it at all.
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
    expect(container.textContent).toContain('b.parquet');
  });

  // The picker asked once, at mount; if the server was still starting, `postRequest` answered
  // `null`, the list stayed empty, and nothing asked again — a reload during the same boot gave
  // the same nothing (owner, 2026-09-18). The button asks again.
  const refresh = (c: HTMLElement) =>
    c.querySelector('button[aria-label="refresh the file list"]') as HTMLButtonElement;

  it('asks the server again on the refresh button, and shows the new answer', async () => {
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
    postRequest.mockImplementation(() => Promise.resolve([...LISTING, { path: 'c.parquet', kind: 'table' }]));
    fireEvent.click(refresh(container));
    await waitFor(() => expect(container.textContent).toContain('c.parquet'));
    expect(postRequest.mock.calls.filter((c) => c[0] === 'list-files').length).toBe(2);
  });

  it('starts empty when the server could not be reached, and can still ask again', async () => {
    postRequest.mockImplementation(() => Promise.resolve(null));
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(refresh(container).disabled).toBe(false));   // the `null` landed
    expect(container.textContent).not.toContain('parquet');
    postRequest.mockImplementation(() => Promise.resolve([{ path: 'a.parquet', kind: 'table' }]));
    fireEvent.click(refresh(container));
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
  });

  it('is disabled while the request is in flight', async () => {
    let answer!: (v: unknown) => void;
    postRequest.mockImplementation(() => new Promise((resolve) => { answer = resolve; }));
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(refresh(container)).not.toBeNull());
    expect(refresh(container).disabled).toBe(true);
    answer([{ path: 'a.parquet', kind: 'table' }]);
    await waitFor(() => expect(refresh(container).disabled).toBe(false));
  });

  it('offers only the files of its kind', async () => {
    // One listing serves three pickers: tables on the Load tab, cards and filters documents on
    // theirs. A cards file must not be offered as a table, nor a table as a document.
    const { container } = render(() => <FilePicker kind="cards" />);
    await waitFor(() => expect(container.textContent).toContain('cards.json'));
    expect(container.textContent).not.toContain('a.parquet');
    expect(container.textContent).not.toContain('sub/filters.json');
    expect(postRequest.mock.calls[0][0]).toBe('list-files');
  });

  it('hands its parent the refresh, so a save can re-list', async () => {
    let refresh!: () => void;
    const { container } = render(() => <FilePicker kind="cards" refreshRef={(f) => { refresh = f; }} />);
    await waitFor(() => expect(container.textContent).toContain('cards.json'));
    postRequest.mockImplementation(() => Promise.resolve([{ path: 'mine.json', kind: 'cards' }]));
    refresh();
    await waitFor(() => expect(container.textContent).toContain('mine.json'));
  });
});
