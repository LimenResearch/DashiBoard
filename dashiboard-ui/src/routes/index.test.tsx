import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';

// Solid 2 defers signal updates, so an interaction and the assertion that depends on it cannot
// share a tick: `flush()` settles the scheduler before the next step.
async function selectOption(select: HTMLSelectElement, value: string) {
  fireEvent.change(select, { target: { value } });
  await flush();
}
import payload from '../fixtures/card-ir.json';
import { flush } from 'solid-js';
import { importConfig, emptyConfig, exportConfig } from '../root';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  loadJSON: vi.fn(),
  downloadJSON: vi.fn(),
  setApiBase: vi.fn(),
  apiBase: () => '',
}));

import Home from './index';

beforeEach(() => {
  importConfig(emptyConfig());
  postRequest.mockReset();
  postRequest.mockImplementation((page: string) =>
    Promise.resolve(page === 'get-card-ir' ? payload : []),
  );
});
afterEach(cleanup);

describe('the card authoring page', () => {
  it('offers every card type the server describes', async () => {
    const { getByLabelText } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    expect([...picker.options].map((o) => o.value).sort()).toContain('split');
    expect(picker.options).toHaveLength(10);
  });

  it('adds a node and renders its form from the IR', async () => {
    const { getByLabelText, getByText, container } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'split');
    fireEvent.click(getByText(/add card/i));

    await waitFor(() => expect(exportConfig().nodes).toHaveLength(1));
    expect(exportConfig().nodes[0].card.type).toBe('split');

    // the variant selector from the split card's `method`, rendered through IRField
    await waitFor(() => {
      const options = [...container.querySelectorAll('select')].flatMap((s) =>
        [...s.options].map((o) => o.value),
      );
      expect(options).toContain('percentile');
      expect(options).toContain('tiles');
    });
  });

  it('shows the authored document, which is what would be saved', async () => {
    const { getByLabelText, getByText, findByTestId } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    const pane = await findByTestId('document');
    await waitFor(() => expect(pane.textContent).toContain('rescale'));
    expect(JSON.parse(pane.textContent ?? '{}')).toEqual(exportConfig());
  });
});
