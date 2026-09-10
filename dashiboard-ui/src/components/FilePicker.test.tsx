import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor } from '@solidjs/testing-library';

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
});
