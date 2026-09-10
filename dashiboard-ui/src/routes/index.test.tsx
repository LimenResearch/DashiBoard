import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';
import { flush } from 'solid-js';
import payload from '../fixtures/card-ir.json';
import { importCards, emptyCards, exportCards } from '../stores';

// Solid 2 defers signal updates, so an interaction and an assertion that depends on it cannot
// share a tick: `flush()` settles the scheduler between them.
async function selectOption(select: HTMLSelectElement, value: string) {
  fireEvent.change(select, { target: { value } });
  await flush();
}

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

const CLEAN_PROBE = { valid: true, cols: [], nodes: [], errors: [] };

beforeEach(() => {
  importCards(emptyCards());
  postRequest.mockReset();
  postRequest.mockImplementation((page: string) => {
    if (page === 'get-card-ir') return Promise.resolve(payload);
    if (page === 'probe-pipeline') return Promise.resolve(CLEAN_PROBE);
    return Promise.resolve([]);
  });
});
afterEach(cleanup);

describe('the authoring page', () => {
  it('offers every card type the server describes', async () => {
    const { getByLabelText } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    expect(picker.options).toHaveLength(10);
    expect([...picker.options].map((o) => o.value)).toContain('split');
  });

  it('adds a card and shows it in the authored document', async () => {
    const { getByLabelText, getByText, findByTestId } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    await waitFor(() => expect(exportCards().nodes).toHaveLength(1));
    expect(exportCards().nodes[0].card.type).toBe('rescale');

    const pane = await findByTestId('document');
    await waitFor(() => expect(pane.textContent).toContain('rescale'));
    // the pane shows the wire document: filters from one store, nodes/groups from the other
    expect(Object.keys(JSON.parse(pane.textContent ?? '{}')).sort())
      .toEqual(['filters', 'groups', 'nodes']);
  });

  it('runs the pipeline with the group dialect the server now takes', async () => {
    const posted: Record<string, unknown>[] = [];
    postRequest.mockImplementation((page: string, body: Record<string, unknown>) => {
      posted.push({ page, body });
      if (page === 'get-card-ir') return Promise.resolve(payload);
      if (page === 'evaluate-pipeline') {
        return Promise.resolve({ graph: 'digraph {a}', report: [{ node: 'split' }] });
      }
      if (page === 'probe-pipeline') return Promise.resolve(CLEAN_PROBE);
      return Promise.resolve([]);
    });

    const { getByLabelText, getByText, findByTestId } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'split');
    fireEvent.click(getByText(/add card/i));
    await flush();

    fireEvent.click(getByText(/run pipeline/i));
    const report = await findByTestId('report');
    await waitFor(() => expect(report.textContent).toContain('split'));

    const run = posted.find((p) => p.page === 'evaluate-pipeline');
    expect(run).toBeDefined();
    // {filters, nodes, groups} -- not the retired {filters, cards}
    expect(Object.keys(run!.body as object).sort()).toEqual(['filters', 'groups', 'nodes']);
  });

  it('surfaces references nothing produces, from the probe route', async () => {
    // A10: `through` names a column by concatenating suffixes and validation only checks the
    // base column, so an unproduced chain is accepted and fails late inside a task. The probe is
    // what turns that into something a form can show.
    postRequest.mockImplementation((page: string) => {
      if (page === 'get-card-ir') return Promise.resolve(payload);
      if (page === 'probe-pipeline') {
        return Promise.resolve({
          valid: false,
          cols: ['TEMP'],
          errors: [],
          // one entry per card in the document: the component indexes them by card position
          nodes: [{ id: 'bad', inputs: ['TEMP_a_a'], outputs: [], unproduced: ['TEMP_a_a'] }],
        });
      }
      return Promise.resolve([]);
    });

    const { getByLabelText, getByText, container } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    await waitFor(() => expect(container.textContent).toContain('TEMP_a_a'));
    expect(container.textContent).toMatch(/nothing produces/i);
  });

  it('shows what a chain resolved to, rather than making the UI compute it', async () => {
    postRequest.mockImplementation((page: string) => {
      if (page === 'get-card-ir') return Promise.resolve(payload);
      if (page === 'probe-pipeline') {
        return Promise.resolve({
          valid: true, cols: ['TEMP'], errors: [],
          nodes: [{ id: 'r', inputs: ['TEMP_rescaled'], outputs: ['TEMP_a'], unproduced: [] }],
        });
      }
      return Promise.resolve([]);
    });
    const { getByLabelText, getByText, container } = render(() => <Home />);
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));
    // the resolved name comes from Julia; nothing here reimplements suffix concatenation
    await waitFor(() => expect(container.textContent).toContain('TEMP_rescaled'));
  });

  it('asks for the IR with the vocabularies the document defines', async () => {
    const { getByLabelText } = render(() => <Home />);
    await waitFor(() => getByLabelText(/card type/i));
    const ask = postRequest.mock.calls.find((c) => c[0] === 'get-card-ir');
    expect(ask).toBeDefined();
    // the group dialect needs all three, since which nodes and groups are referenceable
    // depends on the document being edited, not only on the source
    expect(Object.keys(ask![1] as object).sort()).toEqual(['cols', 'groups', 'nodes']);
  });
});
