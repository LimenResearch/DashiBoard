import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, cleanup, waitFor } from '@solidjs/testing-library';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(), downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));

import { TableView } from './TableView';

const fetches = () => postRequest.mock.calls.filter((c) => c[0] === 'fetch-data');

beforeEach(() => {
  postRequest.mockReset();
  postRequest.mockImplementation((page: string) =>
    Promise.resolve(page === 'fetch-data' ? { values: [{ TEMP: 1 }, { TEMP: 2 }], length: 2 } : []),
  );
});
afterEach(cleanup);

describe('TableView at mount', () => {
  it('asks for block 0 once, not twice', async () => {
    // The grid is created with neither columns nor datasource; both arrive through effects.
    // ag-grid defers starting the row model until it has columns, and that deferred start calls
    // `setDatasource` itself — so if the datasource is pushed *before* the columns, the row model
    // builds one cache (request 1), then the columns arrive, start runs, and it builds a second
    // cache (request 2), throwing the first answer away. Columns first, and there is one request.
    // Traced 2026-09-16 through InfiniteRowModel.setDatasource / SyncService.setColumnsAndData.
    render(() => <TableView processed={false} metadata={[{ name: 'TEMP', eltype: 'float' }]} revision={0} />);
    await waitFor(() => expect(fetches().length).toBeGreaterThan(0), { timeout: 2000 });
    // The block loader runs on a timer; give a second request every chance to show up.
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(fetches().map((c) => (c[1] as { offset: number }).offset)).toEqual([0]);
  });
});
