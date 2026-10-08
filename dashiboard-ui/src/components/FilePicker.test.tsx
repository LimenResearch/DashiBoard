import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  downloadJSON: vi.fn(),
  setApiBase: vi.fn(),
  apiBase: () => '',
}));

import { FilePicker } from './FilePicker';
import { setFolders } from '../folders';

// What `list-files` answers: every file the UI may pick, with what it is. One listing serves
// three pickers, so each test says which kind it is looking through.
const FILES = [
  { path: 'a.parquet', kind: 'table' },
  { path: 'b.parquet', kind: 'table' },
  { path: 'cards.json', kind: 'cards' },
  { path: 'sub/filters.json', kind: 'filters' },
];
const LISTING = { files: FILES, misplaced: [] };
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
    postRequest.mockImplementation(() => Promise.resolve({ files: [...FILES, { path: 'c.parquet', kind: 'table' }], misplaced: [] }));
    fireEvent.click(refresh(container));
    await waitFor(() => expect(container.textContent).toContain('c.parquet'));
    expect(postRequest.mock.calls.filter((c) => c[0] === 'list-files').length).toBe(2);
  });

  it('starts empty when the server could not be reached, and can still ask again', async () => {
    postRequest.mockImplementation(() => Promise.resolve(null));
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(refresh(container).disabled).toBe(false));   // the `null` landed
    expect(container.textContent).not.toContain('parquet');
    postRequest.mockImplementation(() => Promise.resolve({ files: [{ path: 'a.parquet', kind: 'table' }], misplaced: [] }));
    fireEvent.click(refresh(container));
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
  });

  it('is disabled while the request is in flight', async () => {
    let answer!: (v: unknown) => void;
    postRequest.mockImplementation(() => new Promise((resolve) => { answer = resolve; }));
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(refresh(container)).not.toBeNull());
    expect(refresh(container).disabled).toBe(true);
    answer({ files: [{ path: 'a.parquet', kind: 'table' }], misplaced: [] });
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
    postRequest.mockImplementation(() => Promise.resolve({ files: [{ path: 'mine.json', kind: 'cards' }], misplaced: [] }));
    refresh();
    await waitFor(() => expect(container.textContent).toContain('mine.json'));
  });

  // A file whose content disagrees with the folder it sits in is not offered, but the author
  // is told why it is missing rather than left to wonder.
  it('says which files of its kind are misplaced, and does not offer them', async () => {
    postRequest.mockImplementation(() => Promise.resolve({
      files: FILES,
      misplaced: [
        { path: 'f.json', kind: 'pipeline', found: 'filters' },
        { path: 't2.csv', kind: 'pipeline', found: 'table' },
        { path: 'p.json', kind: 'filter', found: 'cards' },
      ],
    }));
    const { container } = render(() => <FilePicker kind="cards" />);
    await waitFor(() => expect(container.querySelectorAll('[data-misplaced]').length).toBe(2));
    const notes = [...container.querySelectorAll('[data-misplaced]')].map((e) => e.textContent);
    expect(notes[0]).toMatch(/f\.json/);
    expect(notes[0]).toMatch(/filters/);
    expect(notes[0]).toMatch(/pipeline\//);
    expect(container.textContent).not.toMatch(/p\.json/);
  });

  it('names the folder the server says it lists, when that is not the layout\'s', async () => {
    postRequest.mockImplementation(() => Promise.resolve({ files: FILES, misplaced: [], folders: { table: 'tables', cards: '', filters: 'filter' } }));
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(container.querySelector('label')!.textContent).toMatch(/tables\//));
    cleanup();
    const cards = render(() => <FilePicker kind="cards" />);
    await waitFor(() => expect(cards.container.querySelector('label')!.textContent).toMatch(/the workspace/));
    setFolders(null);
  });

  it('names the folder it lists in its label', async () => {
    const { container } = render(() => <FilePicker kind="table" multiple />);
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
    expect(container.querySelector('label')!.textContent).toMatch(/data\//);
    cleanup();
    const cards = render(() => <FilePicker kind="cards" />);
    expect(cards.container.querySelector('label')!.textContent).toMatch(/pipeline\//);
  });
});
