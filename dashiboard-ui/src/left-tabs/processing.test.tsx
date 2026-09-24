import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, cleanup, waitFor, fireEvent } from '@solidjs/testing-library';
import { flush, reconcile } from 'solid-js';
import payload from '../fixtures/card-ir.json';
import {
  importCards, addGroup, addNode, removeNode, setNodeId, setCardField, confirmDefinition, rejectFromIssues, exportCards,
  forgetAllVerdicts, PROBE_STORE, emptyProbe, recordVerdict, documentVerdict, setDroppedReferences,
  PRESETS_STORE,
} from '../stores';

const postRequest = vi.fn();
vi.mock('../requests', () => ({
  postRequest: (...args: unknown[]) => postRequest(...args),
  getURL: (page: string) => `/${page}`,
  downloadJSON: vi.fn(), setApiBase: vi.fn(), apiBase: () => '',
}));
// Choosing in a Choices.js widget is the picker's own tests' business (`loading.test.tsx` mocks
// it the same way). `Documents` stays real: the last block here is its integration with the tab.
vi.mock('../components/FilePicker', () => ({
  FilePicker: (props: { onChange?: (v: string) => void }) =>
    <button data-pick onClick={() => props.onChange?.('doc.json')}>pick</button>,
}));

import { Cards } from './processing';

const CLEAN_PROBE = { valid: true, cols: [], nodes: [], errors: [], issues: [] };

beforeEach(() => {
  sessionStorage.clear();
  postRequest.mockReset();
  postRequest.mockImplementation((page: string, body: unknown) =>
    Promise.resolve(
      page === 'get-card-ir'
        ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                   const full = structuredClone(payload) as Record<string, unknown>;
                   return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
      : page === 'probe-pipeline' ? CLEAN_PROBE
      : page === 'validate-card' ? { valid: true, issues: [] }
      : [],
    ),
  );
  importCards({
    nodes: [{ id: 'r', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } }],
    groups: { g: [] },
  });
  // `PROBE_STORE` is a module-level store, same as `CARDS_STORE` — `test.isolate: false` shares it
  // across every file in this run, and a test that seeds it (`rejectFromIssues`, or a mocked
  // `probe-pipeline` reply carrying issues) must not leak that into the next test's render. See the
  // identical reset in `GroupsEditor.test.tsx` and `routes/index.test.tsx`.
  PROBE_STORE[1](reconcile(emptyProbe()));
  // Presets are a module-level store too, and a test that sets one must not leak it.
  PRESETS_STORE[1](reconcile({}));
  // Verdicts are a module-level signal too; clearing `sessionStorage` does not empty it.
  forgetAllVerdicts();
});
afterEach(cleanup);

const irCalls = () => postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir').length;

describe('an IR refetch', () => {
  it('leaves the card form and the groups editor in place', async () => {
    // Adding a group changes the vocabulary, which refetches the IR. The payload is a new object
    // every time, and three `<Show keyed>`s were keyed on it — so every card form and the whole
    // groups editor were torn down and rebuilt, folding open groups and losing picker state.
    // Measured 2026-09-15 by exactly this comparison.
    const { container } = render(() => <Cards />);
    const q = (sel: string) => container.querySelector(sel);
    await waitFor(() => { if (!q('#node-0-rescale-method-variant') && !q('#method-variant')) throw new Error('form not up'); });

    const before = {
      select: q('#method-variant') ?? q('#node-0-rescale-method-variant'),
      groupInput: q('#group-name-g'),
      groupPicker: q('[data-tabs="kinds"]'),
    };
    const groupDetails = [...container.querySelectorAll('details')].find((d) =>
      d.querySelector('#group-name-g'),
    )!;
    groupDetails.open = true;

    const n = irCalls();
    addGroup();
    await waitFor(() => expect(irCalls()).toBe(n + 1));
    await flush();
    await new Promise((r) => setTimeout(r, 30));
    await flush();

    expect(q('#method-variant') ?? q('#node-0-rescale-method-variant')).toBe(before.select);
    expect(q('#group-name-g')).toBe(before.groupInput);
    expect(q('[data-tabs="kinds"]')).toBe(before.groupPicker);
    expect(groupDetails.open).toBe(true);
  });
});

describe('the continuous probe', () => {
  const probeCalls = () => postRequest.mock.calls.filter((c) => c[0] === 'probe-pipeline');

  it('coalesces a burst of edits into one request', async () => {
    // It fired one POST per committed edit. Every keystroke that commits — every field, every
    // chip — became a document-wide resolve on the server.
    vi.useFakeTimers();
    try {
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);   // settle the mount-time probe
      const n = probeCalls().length;
      setNodeId(0, 'a'); await flush();
      setNodeId(0, 'ab'); await flush();
      setNodeId(0, 'abc'); await flush();
      await vi.advanceTimersByTimeAsync(100);
      expect(probeCalls().length).toBe(n);        // still inside the quiet window
      await vi.advanceTimersByTimeAsync(200);
      expect(probeCalls().length).toBe(n + 1);    // one request for three edits
    } finally {
      vi.useRealTimers();
    }
  });

  it('discards a reply that arrives after a newer request was sent', async () => {
    // Replies are async and the server is not obliged to answer in order. Without a guard the
    // slow answer to the *old* document overwrote the fast answer to the new one.
    vi.useFakeTimers();
    const pending: Array<(v: unknown) => void> = [];
    postRequest.mockImplementation((page: string, body: { nodes?: { id: string }[] }) => {
      if (page === 'get-card-ir') return Promise.resolve(structuredClone(payload));
      if (page === 'probe-pipeline') {
        return new Promise((resolve) => pending.push((v) => resolve({ ...CLEAN_PROBE, cols: [body.nodes?.[0]?.id ?? ''] , ...(v as object) })));
      }
      return Promise.resolve([]);
    });
    try {
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      const { PROBE_STORE } = await import('../stores');
      setNodeId(0, 'first'); await flush(); await vi.advanceTimersByTimeAsync(250);
      setNodeId(0, 'second'); await flush(); await vi.advanceTimersByTimeAsync(250);
      expect(pending.length).toBeGreaterThanOrEqual(2);
      const [old, fresh] = pending.slice(-2);
      fresh({}); await flush(); await vi.advanceTimersByTimeAsync(0);
      old({});   await flush(); await vi.advanceTimersByTimeAsync(0);
      expect(PROBE_STORE[0].cols).toEqual(['second']);   // the old reply did not win
    } finally {
      vi.useRealTimers();
    }
  });

  it('runs for a groups-only document', async () => {
    // Groups first is the usual authoring order, and an empty group is a server-side finding —
    // so short-circuiting on "no cards" left a groups-only document with no live finding at all
    // until the first card existed (final review, 2026-09-16).
    vi.useFakeTimers();
    try {
      importCards({ nodes: [], groups: { g: [] } });
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      expect(probeCalls().length).toBe(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('stays quiet for a document with nothing in it', async () => {
    // Nothing to resolve, so nothing to ask: an empty document still answers locally.
    vi.useFakeTimers();
    try {
      importCards({ nodes: [], groups: {} });
      render(() => <Cards />);
      await vi.advanceTimersByTimeAsync(300);
      expect(probeCalls().length).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it('does not outlive the tab that scheduled it', async () => {
    // An edit schedules a probe 200 ms out. Unmounting inside that window used to leave the timer
    // running, so a POST went out for a tab that no longer exists — and with real timers it
    // landed in whatever ran next, which is what made the test above flaky on a slow worker.
    render(() => <Cards />);
    await waitFor(() => expect(irCalls()).toBe(1));
    await new Promise((r) => setTimeout(r, 250)); await flush();   // let the mount-time probe go
    const before = probeCalls().length;
    addGroup(); await flush();                                     // schedules a probe in 200 ms
    cleanup();                                                     // the tab goes away first
    await new Promise((r) => setTimeout(r, 300)); await flush();
    expect(probeCalls().length).toBe(before);
  });
});

describe('a warning from the probe', () => {
  it('renders in the warning style and does not block Confirm', async () => {
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? { ...CLEAN_PROBE, issues: [{ pointer: '/nodes/0/card', reason: 'overwrites', severity: 'warning', found: null, allowed: null, missing: [], related: [], message: '`TEMP_z` already exists and will be replaced' }] }
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(container.querySelector('[data-issue-severity="warning"]')!.className).toMatch(/warning/);
    // `getAllByText('Confirm')[0]` would press the groups editor's Confirm — it renders above the
    // cards and `beforeEach` seeds group `g`. The card's own Confirm carries this title.
    fireEvent.click(container.querySelector('button[title="mark this card deliberately finished"]')!);
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
  });
});

describe('a card whose probe could not be reached', () => {
  it('reads as "could not check", never as a clean card, and does not confirm', async () => {
    // `validate-card` still answers cleanly — the card's own schema is fine — but the whole-document
    // probe `confirmNode` asks next resolves to `null` (item 1's missing proxy route, mocked here
    // as `postRequest`'s own failure default).
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'validate-card' ? { valid: true, issues: [] }
        : page === 'probe-pipeline' ? null
        : [],
      ),
    );
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('button[title="mark this card deliberately finished"]')).not.toBeNull());
    fireEvent.click(container.querySelector('button[title="mark this card deliberately finished"]')!);
    await waitFor(() => expect(container.textContent).toMatch(/could not reach/i));
    expect(container.querySelector('[data-state="confirmed"]')).toBeNull();
  });
});

describe('a card is amber until asked', () => {
  // Decided 2026-09-17: red is reserved for "you asked, and it was wrong". The continuous probe
  // keeps running (it feeds the resolved names, the warnings and the pointer next to Run) but its
  // errors no longer paint the card — no red finding, no red dot — until Confirm or a Run asks.
  // A verdict binds to the card's content, so an edit returns it to amber and drops its findings.
  const cardDot = (container: HTMLElement) =>
    [...container.querySelectorAll('details')]
      .find((d) => d.querySelector('[data-card-title]'))!
      .querySelector('[data-state]')!;
  const cardConfirm = (container: HTMLElement) =>
    container.querySelector('button[title="mark this card deliberately finished"]')!;
  const BROKEN = {
    pointer: '/nodes/0/card', reason: 'required', severity: 'error' as const, found: null, allowed: null,
    missing: ['inputs'], related: ['/nodes/0/card/inputs'], message: 'Schema Validation Error',
  };
  const mock = (probe: unknown, card: unknown) =>
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? probe
        : page === 'validate-card' ? card
        : [],
      ),
    );

  it('shows no red before Confirm, even while the probe reports an error for it', async () => {
    mock({ ...CLEAN_PROBE, valid: false, issues: [BROKEN] }, { valid: false, issues: [BROKEN] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    // The continuous probe has answered once its verdict reached the store.
    await waitFor(() => expect(PROBE_STORE[0].valid).toBe(false));
    await flush();
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
    expect(cardDot(container).className).toMatch(/bg-warning/);
    expect(container.querySelector('[data-issue-severity="error"]')).toBeNull();
    expect(container.querySelector('[data-finding]')).toBeNull();
    expect(container.textContent).not.toMatch(/schema validation/i);
  });

  it('turns red with its findings on Confirm, and amber again on edit', async () => {
    mock(CLEAN_PROBE, { valid: false, issues: [BROKEN] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('rejected'));
    expect(cardDot(container).className).toMatch(/bg-destructive/);
    expect(container.querySelector('[data-finding]')!.textContent).toMatch(/inputs.*needs a value/);
    setCardField(0, 'suffix', 'edited');
    await flush();
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed'));
    expect(container.querySelector('[data-finding]')).toBeNull();
  });

  it('turns green on a clean Confirm, and a live warning leaves it green', async () => {
    const warning = { ...BROKEN, reason: 'overwrites', severity: 'warning' as const, missing: [], related: [], message: '`TEMP_z` already exists' };
    mock({ ...CLEAN_PROBE, issues: [warning] }, { valid: true, issues: [] });
    const { container } = render(() => <Cards />);
    // The warning renders live, amber, before anyone asks — and the dot stays amber too.
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('confirmed'));
    await waitFor(() => expect(container.querySelector('[data-issue-severity="warning"]')).not.toBeNull());
    expect(cardDot(container).getAttribute('data-state')).toBe('confirmed');
    expect(cardDot(container).className).toMatch(/bg-success/);
  });

  it('binds the verdict to the card as it was checked, not as it is when the reply lands', async () => {
    // Press Confirm, edit while `validate-card` is in flight, then let it answer clean: the verdict
    // is green on the content the server saw, and the edited card reads as unasked.
    let answerCard: (v: unknown) => void = () => {};
    postRequest.mockImplementation((page: string) =>
      page === 'get-card-ir' ? Promise.resolve(structuredClone(payload))
      : page === 'probe-pipeline' ? Promise.resolve(CLEAN_PROBE)
      : page === 'validate-card' ? new Promise((resolve) => { answerCard = resolve; })
      : Promise.resolve([]));
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    const checked = exportCards().nodes[0];
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(postRequest.mock.calls.some((c) => c[0] === 'validate-card')).toBe(true));
    setCardField(0, 'suffix', 'edited-in-flight');
    await flush();
    answerCard({ valid: true, issues: [] });
    const { verdictOf } = await import('../stores');
    await waitFor(() => expect(verdictOf('node:0', checked)?.verdict).toBe('confirmed'));
    expect(verdictOf('node:0', exportCards().nodes[0])).toBeNull();
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
  });

  it('a failed run before any Confirm turns the card red with the run\'s findings', async () => {
    mock(CLEAN_PROBE, { valid: true, issues: [] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    rejectFromIssues([BROKEN]);
    await flush();
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('rejected'));
    expect(container.querySelector('[data-finding]')!.textContent).toMatch(/needs a value/);
  });

  it('leaves a confirmed card confirmed when the live probe only warns', async () => {
    const issueFor = (severity: 'error' | 'warning') => ({ ...BROKEN, reason: 'overwrites', severity, missing: [], related: [], message: '`TEMP_z` already exists' });
    confirmDefinition('node:0', exportCards().nodes[0]);
    const issue = issueFor('warning');
    rejectFromIssues([issue]);
    postRequest.mockImplementation((page: string) =>
      Promise.resolve(
        page === 'get-card-ir' ? structuredClone(payload)
        : page === 'probe-pipeline' ? { ...CLEAN_PROBE, issues: [issue] }
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull();
  });
});

describe('the card IR', () => {
  it('is fetched whole once, then only its vocabulary', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(irCalls()).toBe(1));
    const first = postRequest.mock.calls.find((c) => c[0] === 'get-card-ir')![1] as { include?: string[] };
    expect(first.include ?? ['defs', 'cards']).toEqual(expect.arrayContaining(['cards']));

    addGroup();
    await waitFor(() => expect(irCalls()).toBe(2));
    const second = postRequest.mock.calls.filter((c) => c[0] === 'get-card-ir')[1][1] as { include?: string[] };
    expect(second.include).toEqual(['defs']);
    // and the form still renders, from the cached cards
    await waitFor(() => expect(container.querySelector('#node-0-rescale-method-variant')).not.toBeNull());
  });
});

describe('the card header', () => {
  it('wraps its actions and truncates its title rather than overflowing', async () => {
    // Check 8 by hand: `dimensionality_reduction : dimensionality_reduction` pushed Remove past
    // the column's edge. jsdom has no layout, so this pins the classes and the full-text title.
    importCards({ nodes: [{ id: 'dimensionality_reduction', card: { type: 'dimensionality_reduction' } }], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-title]')).not.toBeNull());
    const summary = container.querySelector('[data-card-title]')!.closest('summary')!;
    expect(summary.className).toMatch(/flex-wrap/);
    // The title unit is a flex container (icon/dot alignment) and stays un-truncated itself:
    // `text-overflow: ellipsis` only renders in a block/inline formatting context, so `truncate`
    // has to sit on the inner, non-flex text run instead — see `data-card-text` below.
    const title = container.querySelector('[data-card-title]')!;
    expect(title.className).toMatch(/min-w-0/);
    expect(title.className).not.toMatch(/truncate/);
    // The kind is the server's own title for the card type, not the raw type name: folded, a
    // card has to read as a card of that kind, and a group as a group.
    expect(title.getAttribute('title')).toBe('Dimensionality Reduction : dimensionality_reduction');
    const text = container.querySelector('[data-card-text]')!;
    expect(text.className).toMatch(/truncate/);
    expect(text.className).not.toMatch(/flex/);
    expect(container.querySelector('[data-card-actions]')!.className).toMatch(/shrink-0/);
  });

  it('keeps Confirm and Remove at the foot of the card, on screen when it is folded', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-card-actions]')).not.toBeNull());
    const actions = container.querySelector('[data-card-actions]')!;
    expect([...actions.querySelectorAll('button')].map((b) => b.textContent)).toEqual(['Confirm', 'Clear', 'Remove']);
    expect(actions.closest('details')).toBeNull();
    const card = actions.parentElement!;
    expect(card.querySelector('details')).not.toBeNull();
    expect(card.lastElementChild).toBe(actions);
  });
});

describe('adding to the pipeline', () => {
  it('adds a group, which is what makes the groups tab in every picker non-empty', async () => {
    importCards({ nodes: [], groups: {} });
    const { getByText, container } = render(() => <Cards />);
    await waitFor(() => expect(getByText('Add group')).toBeDefined());
    fireEvent.click(getByText('Add group'));
    await flush();
    expect((container.querySelector('input[aria-label="group name"]') as HTMLInputElement).value).toBe('group');
    expect(exportCards().groups).toEqual({ group: [] });
  });

  it('puts the hand on the new item: its name box takes the focus, and the item stays folded', async () => {
    importCards({ nodes: [], groups: {} });
    const { getByText, container } = render(() => <Cards />);
    await waitFor(() => expect(getByText('Add card')).toBeDefined());
    fireEvent.click(getByText('Add group'));
    await flush(); await new Promise((done) => requestAnimationFrame(() => done(null)));
    const groupName = container.querySelector('input[aria-label="group name"]') as HTMLInputElement;
    expect(document.activeElement).toBe(groupName);
    expect(groupName.closest('details')!.open).toBe(false);
    fireEvent.click(getByText('Add card')); await flush();
    fireEvent.click(container.querySelector('[data-card-type="rescale"]')!);
    await flush(); await new Promise((done) => requestAnimationFrame(() => done(null)));
    const cardName = container.querySelector('#node-id-0') as HTMLInputElement;
    expect(document.activeElement).toBe(cardName);
    expect(cardName.closest('details')!.open).toBe(false);
  });

  it('offers Add group and Add card together after the last item, before the pipeline files, and keeps them on screen', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-add]')).not.toBeNull());
    const add = container.querySelector('[data-add]')!;
    expect([...add.querySelectorAll('button')].map((b) => b.textContent?.trim())).toEqual(['Add group', 'Add card', 'Presets', 'ⓘ']);
    // The help sits apart, at the far end of the row.
    expect(add.lastElementChild!.querySelector('[data-help]')).not.toBeNull();
    expect(add.className).toMatch(/sticky/);
    expect(add.nextElementSibling).toBe(container.querySelector('[data-documents]'));
    const lastItem = [...container.querySelectorAll('details')].at(-1)!;
    expect(lastItem.compareDocumentPosition(add) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });
});

describe("a card's name", () => {
  // Owner's browser check, 2026-09-17: two cards took the same name, and the only sign was
  // "Needs attention: the document" — the server's error for it carries no pointer, so no card
  // could show it. Refused where it is typed, as a second group's name is.
  const two = () => importCards({
    nodes: [
      { id: 'a', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } },
      { id: 'b', card: { type: 'rescale', method: { type: 'minmax' }, inputs: [] } },
    ],
    groups: {},
  });
  const nameField = (container: HTMLElement, at: number) =>
    container.querySelector(`#node-id-${at}`) as HTMLInputElement;
  const type = async (container: HTMLElement, at: number, text: string) => {
    const field = nameField(container, at);
    field.value = text;
    fireEvent.change(field);
    await flush();
  };

  it('refuses a name another card already has: the document keeps both names, the field goes back, the card says why', async () => {
    two();
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(nameField(container, 1)).not.toBeNull());
    await type(container, 1, 'a');
    expect(exportCards().nodes.map((node) => node.id)).toEqual(['a', 'b']);
    expect(nameField(container, 1).value).toBe('b');
    const said = container.querySelectorAll('[data-name-error]');
    expect(said.length).toBe(1);
    expect(said[0].textContent).toContain('"a"');
    // On the card that was refused, not the one that owns the name.
    expect(said[0].closest('details')).toBe(nameField(container, 1).closest('details'));
  });

  it('stacks the refusal with the card\'s other banners, under the line that holds the name', async () => {
    // As for groups: one stack of banners, then the fields. A card's findings used to sit under
    // its name field, so the refusal had nowhere to go that was both with them and above it.
    two();
    recordVerdict('node:1', exportCards().nodes[1], 'rejected', [{ message: 'needs a value' }]);
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(nameField(container, 1)).not.toBeNull());
    await type(container, 1, 'a');
    const card = nameField(container, 1).closest('details')!;
    const finding = card.querySelector('[data-finding]')!;
    const said = card.querySelector('[data-name-error]')!;
    expect(finding.nextElementSibling).toBe(said);
    expect(nameField(container, 1).closest('summary')).not.toBeNull();   // the name is in the line above them
  });

  it('stops saying so once the card takes a free name', async () => {
    two();
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(nameField(container, 1)).not.toBeNull());
    await type(container, 1, 'a');
    await type(container, 1, 'c');
    expect(exportCards().nodes.map((node) => node.id)).toEqual(['a', 'c']);
    expect(container.querySelector('[data-name-error]')).toBeNull();
  });
});

describe('Confirm on a document that cannot build', () => {
  // Measured 2026-09-17 with the server's own replies: two cards named `a`, or a loop, come
  // back `valid:false` with the sentence in `errors` and `issues: []` — no item to point at —
  // and Confirm went green. The fault is the document's, so whichever item is asked carries it.
  const cardConfirm = (c: HTMLElement) =>
    c.querySelector('button[title="mark this card deliberately finished"]')!;
  const cardDot = (c: HTMLElement) =>
    [...c.querySelectorAll('details')].find((d) => d.querySelector('[data-card-title]'))!
      .querySelector('[data-state]')!;
  const serveProbe = (reply: unknown) =>
    postRequest.mockImplementation((page: string, body: unknown) =>
      Promise.resolve(
        page === 'get-card-ir'
          ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                     const full = structuredClone(payload) as Record<string, unknown>;
                     return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
        : page === 'probe-pipeline' ? reply
        : page === 'validate-card' ? { valid: true, issues: [] }
        : [],
      ),
    );

  // Revised 2026-09-18, after seeing it in a browser: a loop is nobody's card, and writing it on
  // whichever card was asked put one sentence on every card. The fault is recorded on the
  // *document* (shown once, next to Run); the card is not vouched for and stays amber.
  const LOOP = 'The input graph contains at least one loop: a, b';
  const loopReply = { valid: false, kind: 'pipeline', cols: [], errors: [LOOP],
    issues: [{ pointer: '', reason: 'loop', severity: 'error', found: null, allowed: null,
      missing: [], related: ['/nodes/0', '/nodes/1'], message: LOOP }] };

  it('leaves the card amber and records the fault on the document', async () => {
    serveProbe(loopReply);
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(documentVerdict()).not.toBeNull());
    expect(documentVerdict()!.findings).toEqual([{ message: LOOP }]);
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
    expect(container.querySelector('[data-finding]')).toBeNull();
  });

  it('does the same for a fault the server only has a sentence for', async () => {
    serveProbe({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['FieldError: type Pipelines.SplitCard has no field `suffix`'] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardConfirm(container)).not.toBeNull());
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(documentVerdict()).not.toBeNull());
    expect(documentVerdict()!.findings[0].message).toContain('SplitCard');
    expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed');
  });

  it('turns a confirmed card amber again: Confirm cannot vouch for it while the document does not build', async () => {
    confirmDefinition('node:0', exportCards().nodes[0]);
    await flush();
    serveProbe(loopReply);
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('confirmed'));
    fireEvent.click(cardConfirm(container));
    await waitFor(() => expect(cardDot(container).getAttribute('data-state')).toBe('unconfirmed'));
  });

  it('rejects the later of two cards with one name itself — that one is a card\'s to fix', async () => {
    // Only a loaded document can hold two cards of one name (`setNodeId` refuses it), and the
    // load marks the later card; Confirm must say the same rather than wipe that mark.
    importCards({
      nodes: [
        { id: 'a', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } },
        { id: 'a', card: { type: 'rescale', method: { type: 'minmax' }, inputs: [] } },
      ],
      groups: {},
    });
    serveProbe({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['ArgumentError: Encountered nodes with equal `id`'] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelectorAll('button[title="mark this card deliberately finished"]').length).toBe(2));
    fireEvent.click(container.querySelectorAll('button[title="mark this card deliberately finished"]')[1]);
    await waitFor(() => expect(container.querySelector('[data-finding]')).not.toBeNull());
    expect(container.querySelector('[data-finding]')!.textContent).toContain('There is already a card called "a".');
  });

  it('confirms green when the only fault is another card\'s, pointed at that card', async () => {
    // A schema failure's `errors` repeats the pointed issue's message; that is card 2's
    // business, and card 1 is fine.
    importCards({
      nodes: [
        { id: 'r', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } },
        { id: 's', card: { type: 'rescale' } },
      ],
      groups: {},
    });
    serveProbe({ valid: false, kind: 'pipeline', cols: [],
      errors: ['1 schema validation error:\nSchema Validation Error for card in node 2'],
      issues: [{ pointer: '/nodes/1/card', reason: 'required', severity: 'error', found: null,
        allowed: null, missing: ['method'], related: ['/nodes/1/card/method'], message: 'Schema Validation Error for card in node 2' }] });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelectorAll('button[title="mark this card deliberately finished"]').length).toBe(2));
    fireEvent.click(container.querySelectorAll('button[title="mark this card deliberately finished"]')[0]);
    await waitFor(() => expect(container.querySelector('[data-state="confirmed"]')).not.toBeNull());
    expect(container.querySelector('[data-state="rejected"]')).toBeNull();
  });
});

describe('loading a cards document asks', () => {
  // Decided 2026-09-18: a broken document is never refused — the form exists to fix it — and
  // loading one is an act of asking: what the server rejects is red on the items, what the UI
  // can place itself (a taken name) is red on the later card, and what nobody can place is said
  // under the document row. Nothing is confirmed green: nobody looked at it. The document comes
  // from the server's data directory (`read-document`), not from a file dialog.
  const dots = (c: HTMLElement) =>
    [...c.querySelectorAll('details')]
      .filter((d) => d.querySelector('[data-card-title]'))
      .map((d) => d.querySelector('[data-state]')!.getAttribute('data-state'));
  const serveDocument = (probe: unknown, doc: unknown) =>
    postRequest.mockImplementation((page: string, body: unknown) =>
      Promise.resolve(
        page === 'get-card-ir'
          ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                     const full = structuredClone(payload) as Record<string, unknown>;
                     return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
        : page === 'probe-pipeline' ? probe
        : page === 'validate-card' ? { valid: true, issues: [] }
        : page === 'read-document' ? { valid: true, document: doc }
        : [],
      ),
    );
  const load = async (container: HTMLElement) => {
    await waitFor(() => expect(container.querySelector('[data-documents="cards"] [data-pick]')).not.toBeNull());
    fireEvent.click(container.querySelector('[data-documents="cards"] [data-pick]')!);
    await flush();
    fireEvent.click([...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Load pipeline')!);
    await flush();
    await new Promise((r) => setTimeout(r, 0));
    await flush();
  };
  const two = {
    nodes: [
      { id: 'a', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [] } },
      { id: 'b', card: { type: 'rescale' } },
    ],
    groups: {},
  };

  it('rejects the items the server points at, and leaves the rest amber', async () => {
    serveDocument({ valid: false, kind: 'pipeline', cols: [],
      errors: ['1 schema validation error:\nSchema Validation Error for card in node 2'],
      issues: [{ pointer: '/nodes/1/card', reason: 'required', severity: 'error', found: null,
        allowed: null, missing: ['method'], related: ['/nodes/1/card/method'], message: 'Schema Validation Error for card in node 2' }] }, two);
    const { container } = render(() => <Cards />);
    await load(container);
    await waitFor(() => expect(dots(container)).toEqual(['unconfirmed', 'rejected']));
    expect(container.querySelector('[data-document-error]')).toBeNull();
    expect(container.querySelector('[data-state="confirmed"]')).toBeNull();
  });

  it('marks the later of two cards with one name, with the UI\'s own sentence', async () => {
    serveDocument({ valid: false, kind: 'pipeline', cols: [], issues: [],
      errors: ['ArgumentError: Encountered nodes with equal `id`'] },
      { ...two, nodes: [two.nodes[0], { ...two.nodes[1], id: 'a' }] });
    const { container } = render(() => <Cards />);
    await load(container);
    await waitFor(() => expect(dots(container)).toEqual(['unconfirmed', 'rejected']));
    expect(container.querySelector('[data-finding]')!.textContent).toContain('There is already a card called "a".');
    // The server's duplicate-id sentence is placed, so it is not repeated under the row.
    expect(container.querySelector('[data-document-error]')).toBeNull();
  });

  it('records what nobody can place on the document, not under the row, and an edit expires it', async () => {
    const LOOP = 'The input graph contains at least one loop: a, b';
    serveDocument({ valid: false, kind: 'pipeline', cols: [], errors: [LOOP],
      issues: [{ pointer: '', reason: 'loop', severity: 'error', found: null, allowed: null,
        missing: [], related: ['/nodes/0', '/nodes/1'], message: LOOP }] }, two);
    const { container } = render(() => <Cards />);
    await load(container);
    await waitFor(() => expect(documentVerdict()).not.toBeNull());
    expect(documentVerdict()!.findings).toEqual([{ message: LOOP }]);
    // Next to Run is where it is said; the document row is for the file, not the pipeline.
    expect(container.querySelector('[data-document-error]')).toBeNull();
    expect(dots(container)).toEqual(['unconfirmed', 'unconfirmed']);
    setCardField(0, 'suffix', 'edited');
    await flush();
    expect(documentVerdict()).toBeNull();
  });

  it('says so when the server cannot be reached for the probe', async () => {
    serveDocument(null, two);
    const { container } = render(() => <Cards />);
    await load(container);
    await waitFor(() => expect(container.querySelector('[data-document-error]')).not.toBeNull());
    expect(container.querySelector('[data-document-error]')!.textContent).toMatch(/could not reach/i);
  });
});

describe('loading a cards document that names what it does not have', () => {
  it('removes the reference before asking, says so in amber, and the notice closes', async () => {
    const doc = { nodes: [{ id: 'r', card: { type: 'rescale', method: { type: 'zscore' }, inputs: [{ cols: 'TEMP' }, { nodes: 'ghost' }] } }], groups: {} };
    postRequest.mockImplementation((page: string, body: unknown) =>
      Promise.resolve(
        page === 'get-card-ir'
          ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                     const full = structuredClone(payload) as Record<string, unknown>;
                     return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
        : page === 'probe-pipeline' ? CLEAN_PROBE
        : page === 'read-document' ? { valid: true, document: doc }
        : [],
      ),
    );
    setDroppedReferences([]);
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-documents="cards"] [data-pick]')).not.toBeNull());
    fireEvent.click(container.querySelector('[data-documents="cards"] [data-pick]')!);
    await flush();
    postRequest.mockClear();
    fireEvent.click([...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Load pipeline')!);
    await waitFor(() => expect(container.querySelector('[data-dropped-references]')).not.toBeNull());
    const notice = container.querySelector('[data-dropped-references]')!;
    expect(notice.textContent).toMatch(/^References removed — not in the table or the document:/);
    expect(notice.textContent).toContain('nodes:ghost from r');
    const asked = postRequest.mock.calls.filter((c) => c[0] === 'probe-pipeline').map((c) => c[1]);
    expect(asked.length).toBeGreaterThan(0);
    for (const sent of asked) expect(JSON.stringify(sent)).not.toContain('ghost');
    expect(exportCards().nodes[0].card.inputs).toEqual([{ cols: 'TEMP' }]);
    fireEvent.click(notice.querySelector('[aria-label="dismiss"]')!);
    await flush();
    expect(container.querySelector('[data-dropped-references]')).toBeNull();
  });
});

describe('an answer that arrives after its card is gone', () => {
  it('is dropped: the card that slid into its place is not marked for a question nobody asked of it', async () => {
    // Cards are keyed by position. Card 0 is asked, removed while the server is still answering,
    // and an identical card slides into position 0: same key, same content, so the content check
    // cannot tell them apart and the late answer used to land on it. Same guard as for groups.
    const same = { type: 'rescale', method: { type: 'zscore' }, inputs: [] };
    importCards({ nodes: [{ id: 'a', card: same }, { id: 'a', card: same }], groups: {} });
    let answer!: (v: unknown) => void;
    postRequest.mockImplementation((page: string, body: unknown) =>
      page === 'validate-card'
        ? new Promise((resolve) => { answer = resolve; })
        : Promise.resolve(page === 'get-card-ir'
            ? (() => { const inc = (body as { include?: string[] })?.include ?? ['defs', 'cards'];
                       const full = structuredClone(payload) as Record<string, unknown>;
                       return Object.fromEntries(inc.map((k) => [k, full[k]])); })()
            : page === 'probe-pipeline' ? CLEAN_PROBE : []));
    const { container } = render(() => <Cards />);
    const confirm = 'button[title="mark this card deliberately finished"]';
    await waitFor(() => expect(container.querySelectorAll(confirm).length).toBe(2));
    fireEvent.click(container.querySelectorAll(confirm)[0]);
    await waitFor(() => expect(answer).toBeDefined());
    removeNode(0);
    await flush();
    answer({ valid: false, issues: [{ pointer: '/nodes/0/card', reason: 'required', severity: 'error', found: null,
      allowed: null, missing: ['inputs'], related: ['/nodes/0/card/inputs'], message: 'x' }] });
    await new Promise((r) => setTimeout(r, 20));
    await flush();
    const dots = [...container.querySelectorAll('details')]
      .filter((d) => d.querySelector('[data-card-title]'))
      .map((d) => d.querySelector('[data-state]')!.getAttribute('data-state'));
    expect(dots).toEqual(['unconfirmed']);
  });
});

describe('a card-IR answer that arrives after a newer one', () => {
  it('is dropped: the pickers offer the names the document has now', async () => {
    // Every vocabulary change refetches the defs. Two changes in quick succession are two
    // requests, and nothing said which answer was the newer: when the first landed last, the
    // pickers went back to offering a node name that no longer existed (measured 2026-09-21).
    // Same guard as the continuous probe's `probeSeq`. It takes a slow server to show.
    const rescale = { type: 'rescale', method: { type: 'zscore' }, inputs: [] };
    importCards({ nodes: [{ id: 'first', card: rescale }, { id: 'reader', card: rescale }], groups: {} });
    const pending: { nodes: string[]; resolve: (v: unknown) => void }[] = [];
    const reply = (nodes: string[], include: string[]) => {
      const full = structuredClone(payload) as unknown as { defs: Record<string, { enum?: string[] }> };
      full.defs.node = { ...full.defs.node, enum: nodes };
      return Object.fromEntries(include.map((k) => [k, (full as unknown as Record<string, unknown>)[k]]));
    };
    let held = false;
    postRequest.mockImplementation((page: string, body: { nodes?: string[]; include?: string[] }) => {
      if (page !== 'get-card-ir') return Promise.resolve(page === 'probe-pipeline' ? CLEAN_PROBE : []);
      const include = body.include ?? ['defs', 'cards'];
      if (!held) return Promise.resolve(reply(body.nodes ?? [], include));
      return new Promise((resolve) => pending.push({ nodes: body.nodes ?? [], resolve }));
    });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('#node-id-1')).not.toBeNull());
    held = true;
    setNodeId(0, 'second'); await flush();
    await waitFor(() => expect(pending.length).toBe(1));
    setNodeId(0, 'third'); await flush();
    await waitFor(() => expect(pending.length).toBe(2));
    pending[1].resolve(reply(pending[1].nodes, ['defs']));      // the newer question answers first
    await new Promise((r) => setTimeout(r, 20)); await flush();
    pending[0].resolve(reply(pending[0].nodes, ['defs']));      // the older one lands last
    await new Promise((r) => setTimeout(r, 20)); await flush();

    const reader = [...container.querySelectorAll('details')].filter((d) => d.querySelector('[data-card-title]'))[1];
    fireEvent.click(reader.querySelector('[role=tab][data-tab="nodes"]')!);
    await flush();
    const offered = [...reader.querySelectorAll('[data-tabs="kinds"]')][0]
      .parentElement!.querySelectorAll('[data-value]');
    expect([...offered].map((e) => e.getAttribute('data-value'))).toEqual(['third']);
  });
});

describe('the Add card menu', () => {
  const button = (c: HTMLElement) => [...c.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Add card')!;
  const items = (c: HTMLElement) => [...c.querySelectorAll('[role=menuitem]')] as HTMLButtonElement[];

  it('is closed until asked, then lists the card types by title and takes the focus', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(button(container)).toBeDefined());
    expect(container.querySelector('[role=menu]')).toBeNull();
    expect(button(container).getAttribute('aria-haspopup')).toBe('menu');
    expect(button(container).getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(button(container)); await flush();
    await new Promise((done) => requestAnimationFrame(() => done(null)));
    expect(button(container).getAttribute('aria-expanded')).toBe('true');
    const byType = Object.fromEntries(items(container).map((b) => [b.getAttribute('data-card-type'), b.textContent]));
    expect(byType.dimensionality_reduction).toBe('Dimensionality Reduction');
    expect(byType.glm).toBe('GLM');
    expect(document.activeElement).toBe(items(container)[0]);
  });

  it('does not take the focus itself, being scrollable', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(button(container)).toBeDefined());
    fireEvent.click(button(container)); await flush();
    expect(container.querySelector('[role=menu]')!.getAttribute('tabindex')).toBe('-1');
  });

  it('adds the type picked, closes, and puts the hand on the new card', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(button(container)).toBeDefined());
    fireEvent.click(button(container)); await flush();
    fireEvent.click(container.querySelector('[data-card-type="glm"]')!); await flush();
    await new Promise((done) => requestAnimationFrame(() => done(null)));
    expect(exportCards().nodes.at(-1)!.card.type).toBe('glm');
    expect(container.querySelector('[role=menu]')).toBeNull();
    expect((document.activeElement as HTMLElement).id).toBe(`node-id-${exportCards().nodes.length - 1}`);
  });

  it('walks with the arrows, and Escape closes it back onto the button', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(button(container)).toBeDefined());
    fireEvent.click(button(container)); await flush();
    await new Promise((done) => requestAnimationFrame(() => done(null)));
    fireEvent.keyDown(items(container)[0], { key: 'ArrowDown' });
    expect(document.activeElement).toBe(items(container)[1]);
    fireEvent.keyDown(items(container)[1], { key: 'ArrowUp' });
    expect(document.activeElement).toBe(items(container)[0]);
    fireEvent.keyDown(items(container)[0], { key: 'Escape' }); await flush();
    expect(container.querySelector('[role=menu]')).toBeNull();
    expect(document.activeElement).toBe(button(container));
  });

  it('closes when the focus leaves it', async () => {
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(button(container)).toBeDefined());
    fireEvent.click(button(container)); await flush();
    fireEvent.focusOut(container.querySelector('[role=menu]')!, { relatedTarget: document.body }); await flush();
    expect(container.querySelector('[role=menu]')).toBeNull();
  });
});

describe('a chain while the document does not build', () => {
  it('is still narrowed by what the server last said about the other cards', async () => {
    const rescale = { type: 'rescale', method: { type: 'zscore' }, inputs: [{ cols: 'TEMP' }] };
    const described = { id: 'r', inputs: ['TEMP'], outputs: ['TEMP_rescaled'], unproduced: [] };
    let valid = true;
    postRequest.mockImplementation((page: string, body: { nodes?: string[]; include?: string[] }) => {
      if (page === 'get-card-ir') {
        const full = structuredClone(payload) as unknown as { defs: Record<string, { enum?: string[] }> };
        full.defs.node = { ...full.defs.node, enum: body.nodes ?? [] };
        return Promise.resolve(Object.fromEntries((body.include ?? ['defs', 'cards']).map((k) => [k, (full as unknown as Record<string, unknown>)[k]])));
      }
      if (page === 'probe-pipeline') return Promise.resolve(valid ? { ...CLEAN_PROBE, nodes: [described] } : { valid: false, cols: [], errors: ['x'], issues: [] });
      return Promise.resolve([]);
    });
    importCards({ nodes: [{ id: 'r', card: rescale }], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(PROBE_STORE[0].nodes.length).toBe(1));
    valid = false;
    addNode({ type: 'rescale' }, 'half');                       // no method: the document no longer builds
    await waitFor(() => expect(PROBE_STORE[0].valid).toBe(false));
    await waitFor(() => expect(container.querySelectorAll('[data-selector]').length).toBeGreaterThanOrEqual(2));
    const field = [...container.querySelectorAll('[data-selector]')].at(-1)!;      // the half-built card's inputs
    const box = field.querySelector('[data-entry]') as HTMLInputElement;
    fireEvent.input(box, { target: { value: 'c' } }); await flush();
    fireEvent.keyDown(box, { key: 'Tab' }); await flush();
    fireEvent.input(box, { target: { value: 'No' } }); await flush();
    fireEvent.keyDown(box, { key: 'Tab' }); await flush();
    // `No` is read by nobody the server described, so no node is offered — not `r`, which reads TEMP
    expect([...field.querySelectorAll('[data-suggestion]')].map((e) => e.getAttribute('data-suggestion'))).toEqual([]);
  });
});

describe('clearing a card', () => {
  it('puts it back to what Add card would make, keeping its type and name', async () => {
    PRESETS_STORE[1](reconcile({ partition: { cols: 'TEMP' } }));
    importCards({ nodes: [{ id: 'r', card: { type: 'rescale', suffix: 'mine', inputs: [{ cols: 'PRES' }] } }], groups: {} });
    const { container } = render(() => <Cards />);
    // The IR has to be in: what a fresh card holds is what the IR declares.
    await waitFor(() => expect(container.querySelector('[data-selector]')).not.toBeNull());
    const actions = [...container.querySelectorAll('[data-card-actions] button')];
    expect(actions.map((b) => b.textContent)).toEqual(['Confirm', 'Clear', 'Remove']);
    // Green, amber, red: what it costs to press, left to right.
    expect(actions[1].className).toContain('text-warning');
    expect(actions[2].className).toContain('text-destructive');
    fireEvent.click(actions[1]); await flush();
    const node = exportCards().nodes[0];
    expect(node.id).toBe('r');
    expect(node.card).toMatchObject({ type: 'rescale', suffix: 'rescaled', partition: { cols: 'TEMP' } });
    expect('inputs' in node.card).toBe(false);          // what was chosen is gone, not emptied
  });
});

describe('presets for new cards', () => {
  const addCard = async (c: HTMLElement, type: string) => {
    fireEvent.click([...c.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Add card')!);
    await flush();
    fireEvent.click(c.querySelector(`[data-card-type="${type}"]`)!); await flush();
  };

  it('starts a new card with the presets its type has a field for', async () => {
    PRESETS_STORE[1](reconcile({ partition: { cols: 'TEMP' }, order_by: [{ cols: 'PRES' }] }));
    importCards({ nodes: [], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-presets]')).not.toBeNull());
    await addCard(container, 'rescale');                       // has partition, not order_by
    expect(exportCards().nodes.at(-1)!.card).toMatchObject({ type: 'rescale', partition: { cols: 'TEMP' } });
    expect('order_by' in exportCards().nodes.at(-1)!.card).toBe(false);
    await addCard(container, 'window_function');               // has order_by, not partition
    expect(exportCards().nodes.at(-1)!.card).toMatchObject({ type: 'window_function', order_by: [{ cols: 'PRES' }] });
    expect('partition' in exportCards().nodes.at(-1)!.card).toBe(false);
  });

  it('leaves a card made before the preset was set alone', async () => {
    importCards({ nodes: [], groups: {} });
    const { container } = render(() => <Cards />);
    await waitFor(() => expect(container.querySelector('[data-presets]')).not.toBeNull());
    await addCard(container, 'rescale');
    expect('partition' in exportCards().nodes[0].card).toBe(false);
    PRESETS_STORE[1](reconcile({ partition: { cols: 'TEMP' } })); await flush();
    expect('partition' in exportCards().nodes[0].card).toBe(false);
  });

});
