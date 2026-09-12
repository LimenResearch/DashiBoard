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

const sectionTabs = (c: HTMLElement) =>
  [...c.querySelectorAll('[data-tabs="sections"] [role=tab]')] as HTMLButtonElement[];
const onScreen = (c: HTMLElement) =>
  [...c.querySelectorAll('section[data-section]')]
    .filter((s) => !s.hasAttribute('hidden'))
    .map((s) => s.getAttribute('data-section'));
/** Bring a page section on screen, the way a reader would. */
async function openTab(c: HTMLElement, name: string) {
  fireEvent.click(sectionTabs(c).find((t) => t.textContent === name)!);
  await flush();
}

describe('the page is a set of tabs', () => {
  it('shows one section at a time, and switches on click', async () => {
    const { container } = render(() => <Home />);
    await waitFor(() => expect(sectionTabs(container).length).toBeGreaterThan(0));
    expect(sectionTabs(container).map((t) => t.textContent)).toEqual([
      'Load', 'Filter', 'Process', 'Run', 'The document',
    ]);
    expect(onScreen(container)).toEqual(['Load']);

    await openTab(container, 'Process');
    expect(onScreen(container)).toEqual(['Process']);
  });

  it('keeps the sections mounted, so switching away does not discard their state', async () => {
    // Load sets up choices.js and Process fetches the card IR; remounting on every switch would
    // refetch and drop each picker's open tab. The stores survive either way — the local state
    // is what does not.
    const { container } = render(() => <Home />);
    await waitFor(() => expect(sectionTabs(container).length).toBeGreaterThan(0));
    const before = postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir').length;
    await openTab(container, 'Run');
    await openTab(container, 'Process');
    expect(postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir')).toHaveLength(before);
  });
});

describe('the authoring page', () => {
  it('offers every card type the server describes', async () => {
    const { container, getByLabelText } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    expect(picker.options).toHaveLength(10);
    expect([...picker.options].map((o) => o.value)).toContain('split');
  });

  it('adds a card and shows it in the authored document', async () => {
    const { container, getByLabelText, getByText, findByTestId } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    await waitFor(() => expect(exportCards().nodes).toHaveLength(1));
    expect(exportCards().nodes[0].card.type).toBe('rescale');

    await openTab(container, 'The document');
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

    const { container, getByLabelText, getByText, findByTestId } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'split');
    fireEvent.click(getByText(/add card/i));
    await flush();

    await openTab(container, 'Run');
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
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    await waitFor(() => expect(container.textContent).toContain('TEMP_a_a'));
    expect(container.textContent).toMatch(/nothing produces/i);
  });

  it('puts a schema failure on the card it addresses, with what would have been accepted', async () => {
    // A7. The pointer is what makes this possible: without it the only honest place for a
    // validation failure is a banner above the whole page, which says nothing about where to fix.
    postRequest.mockImplementation((page: string) => {
      if (page === 'get-card-ir') return Promise.resolve(payload);
      if (page === 'probe-pipeline') {
        return Promise.resolve({
          valid: false,
          cols: ['TEMP'],
          errors: ['Schema Validation Error for card in node 1'],
          nodes: [],
          issues: [
            {
              pointer: '/nodes/0/card/inputs/2/cols',
              reason: 'enum',
              found: 'NOSUCHCOLUMN',
              allowed: ['No', 'TEMP', 'PRES'],
              missing: [],
              related: [],
              message: 'Schema Validation Error',
            },
          ],
        });
      }
      return Promise.resolve([]);
    });

    const { getByLabelText, getByText, container } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    // The field, counted the way a person counts: the pointer's `/2` is the 3rd input.
    // Asserted on the element rather than as a substring of the page — `toContain` here also
    // passes for `card → inputs → 3 → cols`, so it fails to pin where the path starts.
    await waitFor(() =>
      expect([...container.querySelectorAll("span.font-mono")].map((e) => e.textContent))
        .toContain('inputs → 3 → cols'),
    );
    expect(container.textContent).toContain('"NOSUCHCOLUMN" is not one of');
    expect(container.textContent).toContain('No, TEMP, PRES');
  });

  it('does not offer a card its own name, as an input or as a pass-through step', async () => {
    // A card naming itself is a cycle, and the server rejects the whole document for it. The
    // fixture's node vocabulary is ["rescale", "split"], and a rescale card is auto-named
    // "rescale" — so this is exactly the case the screen was getting wrong.
    const { getByLabelText, getByText, container } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));
    await flush();

    const nodeTabs = [...container.querySelectorAll('[role=tab][data-tab="nodes"]')];
    expect(nodeTabs.length).toBeGreaterThan(0);
    for (const tab of nodeTabs) {
      fireEvent.click(tab);
    }
    await flush();

    const offered = [...container.querySelectorAll('[data-value]')]
      .map((e) => e.getAttribute('data-value'));
    expect(offered).toContain('split');
    expect(offered).not.toContain('rescale');

    // The same vocabulary feeds the pass-through composer, so it must be narrowed there too.
    // The composer opens per value, so one has to be opened to see what it offers.
    const row = container.querySelector('[data-value="split"]')!;
    fireEvent.click(row.querySelector('[role=switch]')!);
    await flush();
    fireEvent.click(container.querySelector('[data-value="split"] [data-specify="through"]')!);
    await flush();
    const builder = container.querySelector('[data-value="split"] [data-chain-builder]')!;
    const names = [...builder.querySelectorAll('button')].map((b) => b.textContent);
    expect(names).toContain('split');
    expect(names).not.toContain('rescale');
  });

  it('folds a card to one line naming its type and the id others refer to it by', async () => {
    const { container, getByLabelText, getByText } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));
    await flush();

    const card = [...container.querySelectorAll('details')].find((d) =>
      d.querySelector('summary')?.textContent?.includes('rescale'),
    ) as HTMLDetailsElement;
    expect(card).toBeDefined();
    expect(card.open).toBe(false);
    // type, then the name the rest of the document refers to it by
    expect(card.querySelector('summary')!.textContent).toContain('rescale');
  });

  it('gives a new card the defaults its IR declares, not just a type', async () => {
    // The form displayed `suffix: rescaled` either way; the document did not carry it, so what
    // was on screen and what a download produced disagreed. `method` stays absent: it is required
    // and the IR names no default option, so it is the author's to answer.
    const { container, getByLabelText, getByText } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));

    await waitFor(() => expect(exportCards().nodes).toHaveLength(1));
    const card = exportCards().nodes[0].card;
    expect(card.type).toBe('rescale');
    expect(card.suffix).toBe('rescaled');
    expect(card.method).toBeUndefined();
  });

  it('refuses to confirm a card DashiBoard would reject, and says so on the folded line', async () => {
    // The UI's own rules cover only what the server *accepts*, so on their own they let an empty
    // card through — `checkNode` sees a name and is satisfied while construction fails on
    // `method` and `inputs`. Confirm has to ask the probe, which already knows.
    postRequest.mockImplementation((page: string) => {
      if (page === 'get-card-ir') return Promise.resolve(payload);
      if (page === 'probe-pipeline') {
        return Promise.resolve({
          valid: false,
          cols: ['TEMP'],
          errors: ['Schema Validation Error for card in node 1'],
          nodes: [],
          issues: [
            {
              pointer: '/nodes/0/card',
              reason: 'required',
              found: null,
              allowed: null,
              missing: ['method', 'inputs'],
              related: [],
              message: 'Schema Validation Error',
            },
          ],
        });
      }
      return Promise.resolve([]);
    });

    const { container, getByLabelText, getByText } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'cluster');
    fireEvent.click(getByText(/add card/i));
    await waitFor(() => expect(exportCards().nodes).toHaveLength(1));

    fireEvent.click(getByText('Confirm'));
    // Confirm asks the probe itself, so the assertion waits on that round trip rather than on a
    // tick — which is the race the old wiring lost.
    await waitFor(() =>
      expect(container.querySelector('[data-state="incomplete"]')).not.toBeNull(),
    );
    expect(container.querySelector('[data-state="confirmed"]')).toBeNull();
    expect(container.querySelector('[data-state="incomplete"]')).not.toBeNull();
    expect(container.textContent).toMatch(/fill in method, inputs/i);
  });

  it('offers Confirm before Remove on a card, so the safe action comes first', async () => {
    // Unwired for now — the placement is what was specified, and it is what a later wiring will
    // have to keep. Order matters: the destructive control should not be the first one reached.
    const { container, getByLabelText, getByText } = render(() => <Home />);
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));
    await flush();

    const card = [...container.querySelectorAll('details')].find((d) =>
      d.querySelector('summary')?.textContent?.includes('rescale'),
    )!;
    const actions = [...card.querySelectorAll('summary button')].map((b) => b.textContent);
    expect(actions).toEqual(['Confirm', 'Remove']);
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
    await openTab(container, 'Process');
    const picker = (await waitFor(() => getByLabelText(/card type/i))) as HTMLSelectElement;
    await selectOption(picker, 'rescale');
    fireEvent.click(getByText(/add card/i));
    // the resolved name comes from Julia; nothing here reimplements suffix concatenation
    await waitFor(() => expect(container.textContent).toContain('TEMP_rescaled'));
  });

  it('asks for the IR with the vocabularies the document defines', async () => {
    const { container, getByLabelText } = render(() => <Home />);
    await openTab(container, 'Process');
    await waitFor(() => getByLabelText(/card type/i));
    const ask = postRequest.mock.calls.find((c) => c[0] === 'get-card-ir');
    expect(ask).toBeDefined();
    // the group dialect needs all three, since which nodes and groups are referenceable
    // depends on the document being edited, not only on the source
    expect(Object.keys(ask![1] as object).sort()).toEqual(['cols', 'groups', 'nodes']);
  });
});
