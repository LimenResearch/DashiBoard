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

beforeEach(() => {
  postRequest.mockReset();
  postRequest.mockImplementation(() => Promise.resolve(['a.parquet', 'b.parquet']));
});
afterEach(cleanup);

describe('FilePicker', () => {
  it('offers the paths the server returns', async () => {
    // `postRequest` is a promise. Whether a plain `createMemo` over one yields the value or the
    // promise itself decides whether `options()` can map over it at all.
    const { container } = render(() => <FilePicker multiple />);
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
    expect(container.textContent).toContain('b.parquet');
  });

  // The picker asked once, at mount; if the server was still starting, `postRequest` answered
  // `null`, the list stayed empty, and nothing asked again — a reload during the same boot gave
  // the same nothing (owner, 2026-09-18). The button asks again.
  const refresh = (c: HTMLElement) =>
    c.querySelector('button[aria-label="refresh the file list"]') as HTMLButtonElement;

  it('asks the server again on the refresh button, and shows the new answer', async () => {
    const { container } = render(() => <FilePicker multiple />);
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
    postRequest.mockImplementation(() => Promise.resolve(['a.parquet', 'c.parquet']));
    fireEvent.click(refresh(container));
    await waitFor(() => expect(container.textContent).toContain('c.parquet'));
    expect(postRequest.mock.calls.filter((c) => c[0] === 'get-acceptable-paths').length).toBe(2);
  });

  it('starts empty when the server could not be reached, and can still ask again', async () => {
    postRequest.mockImplementation(() => Promise.resolve(null));
    const { container } = render(() => <FilePicker multiple />);
    await waitFor(() => expect(refresh(container).disabled).toBe(false));   // the `null` landed
    expect(container.textContent).not.toContain('parquet');
    postRequest.mockImplementation(() => Promise.resolve(['a.parquet']));
    fireEvent.click(refresh(container));
    await waitFor(() => expect(container.textContent).toContain('a.parquet'));
  });

  it('is disabled while the request is in flight', async () => {
    let answer!: (v: unknown) => void;
    postRequest.mockImplementation(() => new Promise((resolve) => { answer = resolve; }));
    const { container } = render(() => <FilePicker multiple />);
    await waitFor(() => expect(refresh(container)).not.toBeNull());
    expect(refresh(container).disabled).toBe(true);
    answer(['a.parquet']);
    await waitFor(() => expect(refresh(container).disabled).toBe(false));
  });
});
